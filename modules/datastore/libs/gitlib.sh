#!/bin/bash

function datastore_push() {
    
    if $SC_DATASTORE_RO_USE
    then
        ntc "Datastore is in readonly mode."
    else
        ## RW use
        
        [[ ! -d $SC_DATASTORE_RW_DIR ]] && return
        
        if [[ ! -d $SC_DATASTORE_RW_DIR/.git ]]
        then
            git init -q "$SC_DATASTORE_RW_DIR"
            
cat > "$SC_DATASTORE_RW_DIR/.gitignore" << EOF
.git.log
.gitignore
EOF
        fi
        
        echo "$NOW $SC_USER $(cd "$SC_DATASTORE_RW_DIR" && git add ./*.json && git commit -m "$SC_USER@$HOSTNAME $*") $*" >> "$SC_DATASTORE_RW_DIR/.git.log"
        
        ## we backup most important data in case we need to fallback to readonly mode
        cat "$SC_DATASTORE_RW_DIR/containers.json" > "$SC_DATASTORE_RO_DIR/containers.json"
        cat "$SC_DATASTORE_RW_DIR/users.json" > "$SC_DATASTORE_RO_DIR/users.json"
    fi
}
