#! /bin/bash

if [[ -d /etc/srvctl/data ]]
then
    echo true
    return
fi

echo false