#!/usr/bin/env bash

#-------------------------------------------------------------------------------------
# Build distribution tool for SenchaCMD v1.0.0
# Anton Fisher <a.fschr@gmail.com>
#
#  app1 >--                 --> ssh node1 (sencha app build) --
#          \               /                                   \
#  app2 >--+--> dscmd.sh --                                     --> local build folder
#          /               \                                   /
#  app3 >--                 --> ssh node2 (sencha app build) --
#
#-------------------------------------------------------------------------------------

echo -e "Build distribution tool for SenchaCMD v1.0.0";

# --- config ---

CONFIG_FILE=.dscmd-config
AGENTS_FILE=.dscmd-agents

# --- global variables ---

CMD_PATH="";
CMD_PATH_DAFAULT="~/bin/Sencha/Cmd/sencha";
AGENT_FREE="1";
AGENT_BUSY="2";
#AGENT_ERROR="0";

declare -a AGENTS_ARRAY;
declare -a AGENTS_STATUSES_ARRAY;
declare -a AGENTS_PIDS_ARRAY;
declare -a APPLICATIONS_ARRAY;

# --- common functions ---

function get_full_file_path {
    local user_home=$( echo "$HOME" | sed 's#/#\\\/#g' );
    local user_home_sed="s#~#$user_home#g";
    local rel_path=$( echo "$1" | sed "$user_home_sed" );
    get_full_file_path_result=$( readlink -e "$rel_path" );
}

# --- util functions ---

function read_config_file {
    while IFS='' read -r line || [[ -n "$line" ]]; do
        IFS='=' read -a line_array <<< "$line";
        eval "${line_array[0]}=${line_array[1]}";
    done < "$CONFIG_FILE";
}

function read_agents_list {
    while IFS='' read -r line || [[ -n "$line" ]]; do
        AGENTS_ARRAY["$AGENTS_ARRAY_COUNT"]="$line";
        AGENTS_STATUSES_ARRAY["$AGENTS_ARRAY_COUNT"]="$AGENT_FREE";
        AGENTS_PIDS_ARRAY["$AGENTS_ARRAY_COUNT"]=0;
    done < "$AGENTS_FILE";
}

function save_agents_list {
    local nl;
    local result;

    > "$AGENTS_FILE";

    unset nl;
    unset result;
    for agent in "${AGENTS_ARRAY[@]}"; do
        if [[ -n "$agent" ]]; then
            if [[ -n "$result" ]]; then
                nl=$'\n';
            fi;
            result="$result$nl$agent";
        fi;
    done;

    if [[ -n "$result" ]] ; then
        echo "$result" > "$AGENTS_FILE";
    else
        > "$AGENTS_FILE";
    fi;
}

function parse_agent {
    IFS=':' read -a parse_agent_result <<< "$1";
}

function check_ssh_agent {
    return $(ssh -o ConnectTimeout=10 "$1" "exit;"); #> /dev/null;
}

function rsync_agent {
    rsync \
        -az \
        --partial \
        --delete \
        --delete-excluded \
        --exclude=/.dscmd-* \
        --exclude=dscmd.sh \
        ./ "$1:~/dscmd";
        #-azvP \

    return $?;
}

function rsync_local_folder {
    rsync \
        -az \
        --partial \
        --delete \
        --delete-excluded \
        --exclude=/.dscmd-* \
        --exclude=dscmd.sh \
        "$1:~/dscmd/$2/" ./"$2";
        #-azvP \

    return $?;
}

function get_free_agent {
    unset get_free_agent_result;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        if [[ "${AGENTS_STATUSES_ARRAY[$i]}" == "$AGENT_FREE" ]]; then
            get_free_agent_result="$i";
        fi;
        i=$(( $i+1 ));
    done;
}

function set_agent_free {
    AGENTS_PIDS_ARRAY["$1"]="0";
    AGENTS_STATUSES_ARRAY["$1"]="$AGENT_FREE";
}

function set_agent_busy {
    AGENTS_PIDS_ARRAY["$1"]="$2";
    AGENTS_STATUSES_ARRAY["$1"]="$AGENT_BUSY";
}

function run_build_on_agent {
    parse_agent "${AGENTS_ARRAY[$1]}";

    echo -e "run build '$2' on ${parse_agent_result[1]}@${parse_agent_result[0]}";

    rsync_agent "${parse_agent_result[1]}@${parse_agent_result[0]}";

    ssh -Cq "${parse_agent_result[1]}@${parse_agent_result[0]}" \
        "cd ~/dscmd/pages/$2; ~/bin/Sencha/Cmd/sencha --plain --quiet --time app build;";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed build application '$2' on ${parse_agent_result[1]}@${parse_agent_result[0]}.";
        return 1;
    fi;

    rsync_local_folder "${parse_agent_result[1]}@${parse_agent_result[0]}" "build/production/${2^}";

    return $?;
}

# --- tool usage functions ---

function f_init {
    echo -e "Master initialization.\n";

    local valid_directory;

    read_config_file;

    unset valid_directory;
    while [[ -z "$valid_directory" ]]; do
        read -p "Enter path to SenchaCMD (default: $CMD_PATH_DAFAULT or previous uses) [ENTER]: " cmd_path_user;
        if [[ -z "$cmd_path_user" ]]; then
            valid_directory=1;
            if [[ -z "$CMD_PATH" ]]; then
                cmd_path_user="$CMD_PATH_DAFAULT";
            else
                cmd_path_user="$CMD_PATH";
            fi;
        else
            valid_directory=1;
        fi;
    done;

    echo -e "CMD_PATH=$cmd_path_user" > "$CONFIG_FILE"

    echo -e "\nSaved to $CONFIG_FILE:";
    cat "$CONFIG_FILE";
}

function f_add_agent {
    echo -e "Add agent wizard.\n";

    unset host;
    while [[ -z "$host" ]]; do
        read -p "Enter agent ip or host [ENTER]: " host;
    done;

    unset username;
    read -p "Enter agent username (default: root) [ENTER]: " username;
    if [[ -z "$username" ]]; then
        username="root";
    fi;

    read_agents_list;

    for agent in "${AGENTS_ARRAY[@]}"; do
        if [[ "$agent" = "$host:$username" ]]; then
            echo "Host already registered.";
            exit 1;
        fi;
    done;

    unset install_script_path;
    while [[ -z "$install_script_path" ]]; do
        read -e -p "Enter path to SenchaCMD installation script [ENTER]: " install_script_path;
    done;

    local install_script_basename=$(basename "$install_script_path");
    local install_script_extension="${install_script_basename##*.}";
    local install_script_filename="${install_script_basename%.*}";
    get_full_file_path "$install_script_path";
    local install_script_realpath="$get_full_file_path_result";

    if [[ "$install_script_extension" != "sh" ]] ; then
        echo "ERROR: file $install_script_realpath is not executable (*.sh).";
        exit 1;
    fi;

    read_config_file;

    echo -e "Copy key to agent $username@$host...";
    ssh-copy-id "$username@$host"; #> /dev/null;
    if [[ $? != 0 ]]; then
        echo "ERROR: failed ssh connection to $username@$host.";
        echo "How to create ssh key: https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2";
        exit 1;
    fi;

    echo -e "Upgrade system on $username@$host...";
    ssh -Ct "$username@$host" "sudo apt-get update && sudo apt-get -y upgrade";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed upgrade system.";
        exit 1;
    fi;

    echo -e "Install 'openjdk-7-jre ruby' on $username@$host...";
    ssh -Ct "$username@$host" "sudo apt-get -y install openjdk-7-jre ruby";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed install Java and Ruby.";
        exit 1;
    fi;

    echo -e "Create 'dscmd' folder on $username@$host...";
    ssh -Ct "$username@$host" "mkdir -p dscmd";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed create folder.";
        exit 1;
    fi;

    echo -e "Copy SenchaCMD installation script ($install_script_realpath) to $username@$host:~/dscmd ...";
    scp "$install_script_realpath" "$username@$host:~/dscmd";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed copy SenchaCMD installation script.";
        exit 1;
    fi;

    echo -e "Run SenchaCMD installation script on $username@$host...";
    ssh -Ct "$username@$host" "cd ~/dscmd; bash ./$install_script_basename;";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed run SenchaCMD installation script.";
        exit 1;
    fi;

    echo -e "Syncronize directory with $username@$host:/dscmd...";
    rsync_agent "$username@$host";
    if [[ $? != 0 ]]; then
        echo "ERROR: failed sync with $username@$host:/dscmd.";
        exit 1;
    fi;

    AGENTS_ARRAY["$AGENTS_ARRAY_COUNT"]="$host:$username";

    save_agents_list;

    echo "OK";
}

function f_remove_agent {
    echo -e "Remove agent.";

    if [[ -z "$1" ]]; then
        echo "ERROR: host missed."
        exit 1;
    fi;

    read_agents_list;

    local i=0
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "$agent";
        if [[ "$1" = "${parse_agent_result[0]}" ]] || [[ "$1" = "--all" ]]; then
            AGENTS_ARRAY["$i"]="";
        fi;
        i=$(( $i+1 ));
    done;

    save_agents_list;
}

function f_agents_list {
    echo -e "Agents list:\n";

    read_agents_list;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "$agent";
        echo -e "#$i: ${parse_agent_result[1]}@${parse_agent_result[0]}";
        i=$(( $i+1 ));
    done;
}

function f_agents_test {
    echo -e "Test SSH connection to agents:\n";

    read_agents_list;

    local i=0;
    for agent in "${AGENTS_ARRAY[@]}"; do
        parse_agent "$agent";
        echo -e "Connect to #$i: ${parse_agent_result[1]}@${parse_agent_result[0]}...";
        check_ssh_agent "${parse_agent_result[1]}@${parse_agent_result[0]}";
        if [[ $? != 0 ]]; then
            echo -e "... ERROR";
        else
            echo -e "... OK";
        fi;
        i=$(( $i+1 ));
    done;
}

function f_build {
    echo -e "Build applications:\n";

    if [[ -z "$1" ]]; then
        echo "ERROR: application list missed."
        exit 1;
    fi;

    IFS=',' read -a APPLICATIONS_ARRAY <<< "$1";

    read_agents_list;

    if [[ "$AGENTS_ARRAY_COUNT" == "0" ]]; then
        echo "ERROR: no agents."
        exit 1;
    fi;

    for application in "${APPLICATIONS_ARRAY[@]}"; do
        runned=0;
        while [[ "$runned" == 0 ]]; do
            get_free_agent;

            if [[ -z "$get_free_agent_result" ]]; then
                sleep 1;
                i=0;
                for pid in "${AGENTS_PIDS_ARRAY[@]}"; do
                    if [[ "$pid" != 0 ]]; then
                        ps -p "${pid}" &>/dev/null;
                        if [[ $? != 0 ]]; then
                            set_agent_free "$i";
                        fi;
                    fi;
                    i=$(( $i+1 ));
                done;
            else
                while read line; do
                    echo -e "[build: $application] $line";
                done < <(run_build_on_agent "$get_free_agent_result" "$application") &
                set_agent_busy "$get_free_agent_result" "$!";
                runned=1;
            fi;
        done;
    done;

    wait;

    echo -e "Done.";
}

function f_usage {
    echo -e "Usage:";
    echo -e "  ./dscmd.sh init";
    echo -e "  ./dscmd.sh add-agent";
    echo -e "  ./dscmd.sh remove-agent [--all]";
    echo -e "  ./dscmd.sh agents-list";
    echo -e "  ./dscmd.sh agents-test";
    echo -e "  ./dscmd.sh build <application1,application2,...>";
}

# --- main ---

if [ "$1" == "init" ]; then
    f_init;
elif [ "$1" == "add-agent" ]; then
    f_add_agent $2;
elif [ "$1" == "remove-agent" ]; then
    f_remove_agent "$2";
elif [ "$1" == "agents-list" ]; then
    f_agents_list;
elif [ "$1" == "agents-test" ]; then
    f_agents_test;
elif [ "$1" == "build" ]; then
    f_build "$2";
else
    f_usage;
fi;
