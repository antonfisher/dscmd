#!/usr/bin/env bash
#-------------------------------------------------------------------------------------
# Build distribution tool for SenchaCMD
# Anton Fisher <a.fschr@gmail.com>
#
#  app1 >--                 --> ssh node1 (sencha app build) --
#          \               /                                   \
#  app2 >--+--> dscmd.sh --                                     --> local build folder
#          /               \                                   /
#  app3 >--                 --> ssh node2 (sencha app build) --
#
#-------------------------------------------------------------------------------------

echo -e "Build distribution tool for SenchaCMD v0.1.3 [beta]";

# --- config ---

CONFIG_FILE=".dscmd-config";
AGENTS_FILE=".dscmd-agents";

# --- global variables ---

START_TIME=$(date +%s);
CMD_PATH="";
CMD_PATH_DAFAULT="~/bin/Sencha/Cmd/sencha";
APPS_PATH="";
APPS_PATH_DAFAULT="pages";
AGENT_FREE="1";
AGENT_BUSY="2";
#AGENT_ERROR="0";

declare -a AGENTS_ARRAY;
declare -a AGENTS_STATUSES_ARRAY;
declare -a AGENTS_PIDS_ARRAY;
declare -a APPLICATIONS_ARRAY;

AGENTS_ARRAY_COUNT=0;
APPLICATIONS_ARRAY_MAX_ITEM_LENGTH=0;

# --- common functions ---

##
# Get full file/directory path
#
# Examples:
#   full_path=$(get_full_path '/tmp');       # /tmp
#   full_path=$(get_full_path '~/..');       # /home
#   full_path=$(get_full_path '../../../');  # /home
#
# $1 - relative path
#
# Returns: absolute path
#
function get_full_path {
    local user_home;
    local user_home_sed;
    local rel_path;
    local result;
    user_home="${HOME//\//\\\/}";
    user_home_sed="s#~#${user_home}#g";
    rel_path=$( echo "${1}" | sed "${user_home_sed}" );
    result=$( readlink -e "${rel_path}" );
    echo "${result}";
}

##
# Check directory
#
# Example:
#   check_directory_exits /tmp 1;
#
# $1 - directory path
# $2 - show error
#
# Returns: 0 - exists / 1 - not exists
#
function check_directory_exits {
    if [[ -d "${1}" ]]; then
        return 0;
    else
        if [[ "${2}" == 1 ]]; then
            echo -e "Directory '${1}' does not exist. Please try again.";
        fi;
        return 1;
    fi;
}

##
# $1 - directory path
#
function ls_directory {
    ls_directory_result=$( ls -m "$1" | sed 's#, #,#g' | tr -d '\n' );
    return "${?}";
}

##
# Convert seconds to human format
#
# $1 - duration in seconds
#
function seconds_to_duration {
    s="${1}";
    h=$((s/60/60%24))
    m=$((s/60%60))
    s=$((s%60))
    local result="";

    if [[ "${h}" != 0 ]]; then
        result="${h} hour(s) ";
    fi;

    if [[ "${m}" != 0 || "${h}" != 0 ]]; then
        result="${result}${m} minute(s) ";
    fi;

    echo "${result}${s} second(s)";
}

# --- util functions ---

function read_config_file {
    touch "${CONFIG_FILE}";
    while IFS='' read -r line || [[ -n "${line}" ]]; do
        IFS='=' read -r -a line_array <<< "${line}";
        eval "${line_array[0]}=\"${line_array[1]}\"";
    done < "${CONFIG_FILE}";
}

##
# $1 - new config string
#
function save_config_file {
    touch "${CONFIG_FILE}";
    echo -e "${1}" > "${CONFIG_FILE}";
}

function read_agents_list {
    touch "${AGENTS_FILE}";
    AGENTS_ARRAY_COUNT="0";
    while IFS='' read -r line || [[ -n "${line}" ]]; do
        AGENTS_ARRAY["${AGENTS_ARRAY_COUNT}"]="${line}";
        AGENTS_STATUSES_ARRAY["${AGENTS_ARRAY_COUNT}"]="${AGENT_FREE}";
        AGENTS_PIDS_ARRAY["${AGENTS_ARRAY_COUNT}"]=0;
        AGENTS_ARRAY_COUNT=$((AGENTS_ARRAY_COUNT+1));
    done < "${AGENTS_FILE}";
}

function save_agents_list {
    local nl;
    local result;

    > "${AGENTS_FILE}";

    unset nl;
    unset result;
    for agent in "${AGENTS_ARRAY[@]}"; do
        if [[ -n "${agent}" ]]; then
            if [[ -n "${result}" ]]; then
                nl=$'\n';
            fi;
            result="${result}${nl}${agent}";
        fi;
    done;

    if [[ -n "${result}" ]]; then
        echo "${result}" > "${AGENTS_FILE}";
    else
        > "${AGENTS_FILE}";
    fi;
}

##
# $1 - agent config string (10.0.0.11:user ---> parse_agent_result=['user', '10.0.0.11'])
#
function parse_agent {
    IFS=':';
    read -r -a parse_agent_result <<< "${1}";
}

##
# $1 - agent address (user@10.0.0.11)
#
function check_ssh_agent {
    ssh -o ConnectTimeout=10 "${1}" "exit"; #> /dev/null;
    return "${?}";
}

##
# $1 - agent address (user@10.0.0.11)
#
function rsync_agent {
    rsync \
        -az \
        --partial \
        --delete \
        --delete-excluded \
        --exclude=/.dscmd-* \
        --exclude=dscmd.sh \
        --timeout=30 \
        ./ "${1}:~/dscmd";
        #-azvP \

    return "${?}";
}

##
# $1 - agent address (user@10.0.0.11)
# $2 - application folder
#
function rsync_local_folder {
    rsync \
        -az \
        --partial \
        --delete \
        --delete-excluded \
        --exclude=/.dscmd-* \
        --exclude=dscmd.sh \
        --timeout=30 \
        "${1}:~/dscmd/${2}/" ./"${2}";
        #-azvP \

    return "${?}";
}

##
# Returns: free arent index
#
function get_free_agent {
    unset get_free_agent_result;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        if [[ "${AGENTS_STATUSES_ARRAY[$i]}" == "${AGENT_FREE}" ]]; then
            get_free_agent_result="${i}";
            break;
        fi;
        i=$((i+1));
    done;
}

##
# $1 - agent index
#
function set_agent_free {
    AGENTS_PIDS_ARRAY["${1}"]=0;
    AGENTS_STATUSES_ARRAY["${1}"]="${AGENT_FREE}";
}

##
# $1 - agent index
# $2 - agent process pid
#
function set_agent_busy {
    AGENTS_PIDS_ARRAY["${1}"]="${2}";
    AGENTS_STATUSES_ARRAY["${1}"]="${AGENT_BUSY}";
}

##
# $1 - agent index
# $2 - application name
# $3 - application index
#
function run_build_on_agent {
    local application;
    local index;
    local agent;
    local agent_exit_code;
    local subprocess_exit_code;

    parse_agent "${AGENTS_ARRAY[$1]}";

    application="${2}"
    index="${3}";
    agent="${parse_agent_result[1]}@${parse_agent_result[0]}";
    agent_exit_code=0;

    while read -r line; do
        subprocess_exit_code="${line//EXIT_CODE:/}";

        if [[ "${subprocess_exit_code}" == "${line}" ]]; then
            index_f=$(printf "% 3d" "${index}");
            postfix=$(printf -v t "%%0%ds" "${APPLICATIONS_ARRAY_MAX_ITEM_LENGTH}" && printf "${t}");
            echo -e "[build ${index_f}/${#APPLICATIONS_ARRAY[@]}: ${application}${postfix:${#application}}] ${line}";
        elif [[ "${subprocess_exit_code}" != "0" ]]; then
            agent_exit_code="${subprocess_exit_code}";
        fi;
    done < <(
        echo -e "run build '${application}' on ${agent}";
        subprocess_exit_code=0;

        if [[ "${subprocess_exit_code}" == 0 ]]; then
            echo -e "Syncronize local directory with agent...";
            rsync_agent "${agent}";
            subprocess_exit_code="${?}";
            if [[ "${subprocess_exit_code}" != 0 ]]; then
                echo -e "ERROR: failed rsync '${2}' from local folder to ${agent} (local --X--> agent).";
            fi;
        fi;

        if [[ "${subprocess_exit_code}" == 0 ]]; then
            ssh -Cq "${agent}" "cd ~/dscmd/${APPS_PATH}/${2}; ${CMD_PATH} --plain --quiet --time app build;";
            subprocess_exit_code="${?}";
            if [[ "${subprocess_exit_code}" != 0 ]]; then
                echo -e "ERROR: failed build application '${2}' on ${agent}.";
            fi;
        fi;

        if [[ "${subprocess_exit_code}" == 0 ]]; then
            rsync_local_folder "${agent}" "build/production/${2^}";
            subprocess_exit_code="${?}";
            if [[ "${subprocess_exit_code}" != 0 ]]; then
                echo -e "ERROR: failed rsync '${2}' from ${agent} to local folder (local <--X-- agent).";
            fi;
        fi;

        echo "EXIT_CODE:${subprocess_exit_code}";
    )

    exit "${agent_exit_code}";
}

# --- tool usage functions ---

function f_config {
    echo -e "Master initialization.\n";

    local text;
    local valid_directory;
    local apps_path_user;
    local cmd_path_user;

    read_config_file;

    unset valid_directory;
    while [[ -z "${valid_directory}" ]]; do
        text="Enter path to applications folder";
        text="$text (default: '${APPS_PATH_DAFAULT}' or previous uses '${APPS_PATH}') [ENTER]: ";
        read -r -e -p "${text}" apps_path_user;
        full_path=$(get_full_path "${apps_path_user}");
        if [[ -z "${apps_path_user}" ]]; then
            valid_directory=1;
            if [[ -z "${APPS_PATH}" ]]; then
                apps_path_user="${APPS_PATH_DAFAULT}";
            else
                apps_path_user="${APPS_PATH}";
            fi;
        elif [[ "${apps_path_user}" == .* || "${apps_path_user}" == /* || "${apps_path_user}" == ~* ]]; then
            echo -e "ERROR: only local directories allowed (without './')...";
        elif check_directory_exits "${full_path}" 1; then
            valid_directory=1;
        fi;
    done;
    apps_path_user="${apps_path_user%/}";
    ls_directory "${apps_path_user}";
    echo -e "Found applications in '${apps_path_user}': ${ls_directory_result}\n";

    unset valid_directory;
    while [[ -z "${valid_directory}" ]]; do
        text="Enter path to SenchaCMD on agents (default: ${CMD_PATH_DAFAULT} or previous uses) [ENTER]: ";
        read -r -e -p "${text}" cmd_path_user;
        if [[ -z "${cmd_path_user}" ]]; then
            valid_directory=1;
            if [[ -z "${CMD_PATH}" ]]; then
                cmd_path_user="${CMD_PATH_DAFAULT}";
            else
                cmd_path_user="${CMD_PATH}";
            fi;
        else
            valid_directory=1;
        fi;
    done;

    save_config_file "APPS_PATH=${apps_path_user}\nCMD_PATH=${cmd_path_user}";

    echo -e "\nSaved to ${CONFIG_FILE}:";
    cat "${CONFIG_FILE}";
}

function f_applications_list {
    echo -e "Applicaitons list will be used for build:";

    read_config_file;

    ls_directory "${APPS_PATH}";

    echo -e "${ls_directory_result}\n";
}

function f_add_agent {
    echo -e "Add agent wizard.\n";

    unset hosts_list;
    while [[ -z "${hosts_list}" ]]; do
        read -r -p "Enter agent ip or host (use ',' to add few agents with same username) [ENTER]: " hosts_list;
    done;

    unset username;
    read -r -p "Enter agent username (default: root) [ENTER]: " username;
    if [[ -z "${username}" ]]; then
        username="root";
    fi;

    read_agents_list;

    unset hosts_array;
    IFS=',' read -r -a hosts_array <<< "${hosts_list}";

    for host in "${hosts_array[@]}"; do
        for agent in "${AGENTS_ARRAY[@]}"; do
            if [[ "${agent}" = "${host}:${username}" ]]; then
                echo -e "\nERROR: Host '${username}@${host}' already registered.\n";
                f_agents_list;
                exit 1;
            fi;
        done;
    done;

    unset install_script_path;
    while [[ -z "${install_script_path}" ]]; do
        read -r -e -p "Enter path to SenchaCMD installation script [ENTER]: " install_script_path;
    done;

    local install_script_basename;
    local install_script_extension;
    local install_script_realpath;
    install_script_basename=$(basename "${install_script_path}");
    install_script_extension="${install_script_basename##*.}";
    install_script_realpath=$(get_full_path "${install_script_path}");

    if [[ "${install_script_extension}" != "sh" ]] ; then
        echo -e "ERROR: file ${install_script_realpath} is not executable (*.sh).";
        exit 1;
    fi;

    read -r -p "Copy ssh key to agent using ssh-copy-id (Y/n) [ENTER]: " skip_copy_ssh_key;
    if [[ "${skip_copy_ssh_key}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        unset skip_copy_ssh_key;
    fi;

    read -r -p "Apt-get update and upgrade agent (Y/n) [ENTER]: " skip_apt_get_update;
    if [[ "${skip_apt_get_update}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        unset skip_apt_get_update;
    fi;

    read -r -p "Install Java and Ruby (Y/n) [ENTER]: " skip_install_dependencies;
    if [[ "${skip_install_dependencies}" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        unset skip_install_dependencies;
    fi;

    read_config_file;

    echo -e "Start...";

    for host in "${hosts_array[@]}"; do
        read_agents_list;

        if [[ -z "${skip_copy_ssh_key}" ]]; then
            echo -e "Copy key to agent ${username}@${host}...";
            ssh-copy-id "${username}@${host}"; #> /dev/null;
            if [[ "${?}" != 0 ]]; then
                echo -e "ERROR: failed ssh connection to ${username}@${host}.";
                echo -e "How to create ssh key: https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2";
                exit 1;
            fi;
        fi;

        if [[ -z "${skip_apt_get_update}" ]]; then
            echo -e "Upgrade system on ${username}@${host}...";
            ssh -Ct "${username}@${host}" "sudo apt-get update && sudo apt-get -y upgrade";
            if [[ "${?}" != 0 ]]; then
                echo -e "ERROR: failed upgrade system.";
                exit 1;
            fi;
        fi;

        if [[ -z "${skip_install_dependencies}" ]]; then
            echo -e "Install 'openjdk-7-jre ruby' on ${username}@${host}...";
            ssh -Ct "${username}@${host}" "sudo apt-get -y install openjdk-7-jre ruby";
            if [[ "${?}" != 0 ]]; then
                echo -e "ERROR: failed install Java and Ruby.";
                exit 1;
            fi;
        fi;

        echo -e "Create 'dscmd' folder on ${username}@${host}...";
        ssh -Ct "${username}@${host}" "mkdir -p dscmd";
        if [[ "${?}" != 0 ]]; then
            echo -e "ERROR: failed create folder.";
            exit 1;
        fi;

        echo -e "Copy SenchaCMD installation script (${install_script_realpath}) to ${username}@${host}:~/dscmd ...";
        scp "${install_script_realpath}" "${username}@${host}:~/dscmd";
        if [[ "${?}" != 0 ]]; then
            echo -e "ERROR: failed copy SenchaCMD installation script.";
            exit 1;
        fi;

        echo -e "Run SenchaCMD installation script on ${username}@${host}...";
        ssh -Ct "${username}@${host}" "cd ~/dscmd; bash ./${install_script_basename}";
        if [[ "${?}" != 0 ]]; then
            echo -e "ERROR: failed run SenchaCMD installation script.";
            exit 1;
        fi;

        echo -e "Syncronize directory with ${username}@${host}:/dscmd...";
        rsync_agent "${username}@${host}";
        if [[ "${?}" != 0 ]]; then
            echo -e "ERROR: failed sync with ${username}@${host}:/dscmd.";
            exit 1;
        fi;

        AGENTS_ARRAY["${AGENTS_ARRAY_COUNT}"]="${host}:${username}";

        save_agents_list;
    done;

    echo -e "Done.";
}

##
# $1 - config '--all' or none
#
function f_remove_agent {
    echo -e "Remove agent.";

    if [[ -z "${1}" ]]; then
        echo -e "ERROR: host missed.";
        exit 1;
    fi;

    read_agents_list;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "${agent}";
        if [[ "${1}" = "${parse_agent_result[0]}" ]] || [[ "${1}" = "--all" ]]; then
            AGENTS_ARRAY["${i}"]="";
        fi;
        i=$((i+1));
    done;

    save_agents_list;
}

function f_agents_list {
    echo -e "Agents list:";

    read_agents_list;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "${agent}";
        echo -e "#${i}: ${parse_agent_result[1]}@${parse_agent_result[0]}";
        i=$((i+1));
    done;
}

function f_agents_test {
    echo -e "Test SSH connection to agents:\n";

    read_agents_list;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "${agent}";
        echo -e "Connect to #${i}: ${parse_agent_result[1]}@${parse_agent_result[0]}...";
        check_ssh_agent "${parse_agent_result[1]}@${parse_agent_result[0]}";
        if [[ "${?}" != 0 ]]; then
            echo -e "... ERROR";
        else
            echo -e "... OK";
        fi;
        i=$((i+1));
    done;
}

##
# $1 - application list or '--all' flag
#
function f_build {
    echo -e "Build applications:\n";

    read_config_file;

    apps_list="${1}";

    if [[ "${1}" = "--all" ]]; then
        ls_directory "${APPS_PATH}";
        apps_list="${ls_directory_result}";
    fi;

    if [[ -z "${apps_list}" ]]; then
        echo -e "ERROR: application list missed / no application found.";
        echo -e "Usage: ./dscmd.sh build [--all] <application1,application2,...>";
        exit 1;
    fi;

    IFS=',' read -r -a APPLICATIONS_ARRAY <<< "${apps_list}";

    # save max application name length for output formating
    for application in "${APPLICATIONS_ARRAY[@]}"; do
        if [[ "${#application}" -gt "${APPLICATIONS_ARRAY_MAX_ITEM_LENGTH}" ]]; then
            APPLICATIONS_ARRAY_MAX_ITEM_LENGTH="${#application}";
        fi;
    done;

    read_agents_list;

    if [[ "${AGENTS_ARRAY_COUNT}" == "0" ]]; then
        echo -e "ERROR: no agents.";
        exit 1;
    fi;

    mkdir -p build/production;

    local index;
    local build_exit_code;

    index=1;
    build_exit_code=0;
    for application in "${APPLICATIONS_ARRAY[@]}"; do
        runned=0;
        while [[ "${runned}" == 0 && "${build_exit_code}" == 0 ]]; do
            get_free_agent;

            if [[ -z "${get_free_agent_result}" ]]; then
                sleep 1;
                i=0;
                for pid in "${AGENTS_PIDS_ARRAY[@]}"; do
                    if [[ "${pid}" != 0 ]]; then
                        ps -p "${pid}" &>/dev/null;
                        if [[ "${?}" != 0 ]]; then
                            set_agent_free "${i}";
                            wait "${pid}";
                            exit_code="${?}";
                            if [[ "${exit_code}" != 0 ]]; then
                                build_exit_code="${exit_code}";
                            fi;
                        fi;
                    fi;
                    i=$((i+1));
                done;
            else
                run_build_on_agent "${get_free_agent_result}" "${application}" "${index}" &
                set_agent_busy "${get_free_agent_result}" "${!}";
                runned=1;
            fi;
        done;
        index=$((index+1));
    done;

    #wait by pids
    wait;

    duration_time=$(seconds_to_duration "$(($(date +%s)-START_TIME))");
    echo -e "\nDuration time: ${duration_time}";

    if [[ "${build_exit_code}" != 0 ]]; then
        echo -e "BUILD FAILED (exit code: ${build_exit_code}).\n";
    else
        echo -e "Done.\n";
    fi;
}

function f_usage {
    echo -e "Usage:";
    echo -e "  ./dscmd.sh config";
    echo -e "  ./dscmd.sh applications-list";
    echo -e "  ./dscmd.sh add-agent";
    echo -e "  ./dscmd.sh remove-agent [--all]";
    echo -e "  ./dscmd.sh agents-list";
    echo -e "  ./dscmd.sh agents-test";
    echo -e "  ./dscmd.sh build [--all] <application1,application2,...>";
}

# --- main ---

if [[ "${1}" == "config" ]]; then
    f_config;
elif [[ "${1}" == "applications-list" ]]; then
    f_applications_list;
elif [[ "${1}" == "add-agent" ]]; then
    f_add_agent;
elif [[ "${1}" == "remove-agent" ]]; then
    f_remove_agent "${2}";
elif [[ "${1}" == "agents-list" ]]; then
    f_agents_list;
elif [[ "${1}" == "agents-test" ]]; then
    f_agents_test;
elif [[ "${1}" == "build" ]]; then
    f_build "${2}";
else
    f_usage;
fi;
