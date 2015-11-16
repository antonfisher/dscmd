# dscmd.sh

Build distribution tool for SenchaCMD.

```
app1 >--                 --> ssh node1 (sencha app build) --
        \               /                                   \
app2 >--+--> dscmd.sh --                                     --> local build folder
        /               \                                   /
app3 >--                 --> ssh node2 (sencha app build) --
```

```
$./dscmd.sh 
Build distribution tool for SenchaCMD v1.0.0
Usage:
  ./dscmd.sh init
  ./dscmd.sh add-agent
  ./dscmd.sh remove-agent [--all]
  ./dscmd.sh agents-list
  ./dscmd.sh agents-test
  ./dscmd.sh build <application1,application2,...>
```

## Installation

* Copy script to your Sencha applications workspace
* Run `$./dscmd.sh init`

## Usage

### Add agents (Ubuntu-based host)
* Run `$./dscmd.sh add-agent`

### Run distributed build
* Run `$./dscmd.sh build applicationName1,applicationName2`

## Under hood
```
while (agents) {
    _ssh_ -> _apt-get install_ -> _install sencha cmd_
}

while (applications) {
    _rsync_ -> _sencha app build_ -> _rsync_
}
```

## Release History

* 1.0.0 Initial release

## License

Copyright (c) 2015 Anton Fisher <a.fschr@gmail.com>

MIT License. Free use and change.
