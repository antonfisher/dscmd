#!/usr/bin/env bash

if [[ -z $1 ]]; then
    echo -e "Usage:\n\$ cd ./dev\n\$ rsync-to.sh /my/destination/folder"
    exit;
fi;

while sleep 2; do
    rsync -v ../dscmd.sh $1;
done;
