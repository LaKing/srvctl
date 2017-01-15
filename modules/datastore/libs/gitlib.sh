#!/bin/bash

function datastore_push() {
    
    [[ ! -d /srvctl/data ]] && return
    
    if [[ ! -d /srvctl/data/.git ]]
    then
        git init -q /srvctl/data
cat > /srvctl/data/.gitignore << EOF
.git.log
.gitignore
users
containers
EOF
    fi
    
    echo "$NOW $SC_USER $(cd /srvctl/data && git add ./*.json && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> /srvctl/data/.git.log
    
}
