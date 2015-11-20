# Build distribution tool for SenchaCMD

![Principle pic](https://github.com/antonfisher/dscmd/raw/master/docs/dscmd-principle.png)

```
$./dscmd.sh 
Build distribution tool for SenchaCMD v0.1.1 [beta]
Usage:
  ./dscmd.sh init
  ./dscmd.sh add-agent
  ./dscmd.sh remove-agent [--all]
  ./dscmd.sh agents-list
  ./dscmd.sh agents-test
  ./dscmd.sh build <application1,application2,...>
```

## Installation

* Copy `dscmd.sh` script to your Sencha applications workspace;
* Run `$./dscmd.sh init`.

## Usage

### Add agents (Ubuntu-based host)
* [Copy ssh key](https://www.digitalocean.com/community/tutorials/how-to-set-up-ssh-keys--2) to agent;
* Run `$./dscmd.sh add-agent`.

### Run distributed build
* Run `$./dscmd.sh build --all` to build all application in applications folder;
* Or run `$./dscmd.sh build applicationName1,applicationName2`.

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
* 0.1.1 Beta release:
    * Support `build --all` flag;
    * Fix: `add-agent`
* 0.1.0 Initial release.

## ToDo
- [x] Configurable application path;
- [x] Show list of applications after script init;
- [x] Build all applicaitons in folder;
- [x] Show build progress;
- [ ] Check application's build exit status;
- [ ] Support for multi add-agent.
- [ ] Show build time;
- [ ] Script command suggestions.
- [ ] Agent monitoring script.

## License
Copyright (c) 2015 Anton Fisher <a.fschr@gmail.com>

MIT License. Free use and change.
