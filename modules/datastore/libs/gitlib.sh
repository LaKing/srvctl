#!/bin/bash

function datastore_push() {
    
    [[ ! -d /srvctl/data ]] && return
    
    if [[ ! -d /srvctl/data/.git ]]
    then
        git init -q /srvctl/data
        echo .git.log >> /srvctl/data/.gitignore
        echo .gitignore >> /srvctl/data/.gitignore
        echo users >> /srvctl/data/.gitignore
        echo containers >> /srvctl/data/.gitignore
    fi
    
    echo "$NOW $SC_USER $(cd /srvctl/data && git add *.json && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> /srvctl/data/.git.log
    
}
