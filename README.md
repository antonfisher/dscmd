# Build distribution tool for SenchaCMD

![Principle pic](https://raw.githubusercontent.com/antonfisher/dscmd/docs/images/dscmd-principle.png)

## Result on Jenkins builds chart
![Result](https://raw.githubusercontent.com/antonfisher/dscmd/docs/images/dscmd-jenkins-builds-chart.png)

__Note:__ 3 distributed VMs used instead one master.

## Installation
* Copy `dscmd.sh` script to your Sencha applications workspace;
    * `wget https://raw.githubusercontent.com/antonfisher/dscmd/master/dscmd.sh -O dscmd.sh`
    * `chmod +x dscmd.sh`
* Run `$./dscmd.sh config`.

## Usage

```
$ ./dscmd.sh
Build distribution tool for SenchaCMD v0.1.2 [beta]
Usage:
  ./dscmd.sh config
  ./dscmd.sh applications-list
  ./dscmd.sh add-agent
  ./dscmd.sh remove-agent [--all]
  ./dscmd.sh agents-list
  ./dscmd.sh agents-test
  ./dscmd.sh build [--all] <application1,application2,...>
```

### Add agents (Ubuntu-based host)
* [Copy ssh key](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2) to agent;
* Run `$ ./dscmd.sh add-agent`.

### Run distributed build
* Run `$ ./dscmd.sh build --all` to build all application in applications folder;
* Or run `$ ./dscmd.sh build applicationName1,applicationName2`.

## Under hood
```
for each agents {
    copy ssh key --> ssh --> apt-get install --> install sencha cmd
}

for each applications {
    rsync --> sencha app build --> rsync
}
```

## Release History
* 0.1.2 Beta release:
    * Configurable application path
    * Show list of applications after script init
    * Show build progress
    * Support for multi-host add-agent command
    * Check application's build exit status
    * Stop build after first fail
* 0.1.1 Beta release:
    * Support `build --all` flag
    * Fix: `add-agent`
* 0.1.0 Initial release

## ToDo
- [x] Show build time
- [x] Rename init -> config
- [x] Show applicaiton list command
- [x] Add agent, ssh-key copying action confirmation
- [x] Add agent, apt-get update confirmation
- [ ] Script commands completion(?)

## License
Copyright (c) 2015 Anton Fisher <a.fschr@gmail.com>

MIT License. Free use and change.
