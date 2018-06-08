#!/bin/bash

function backupdb() {
    
    if [[ -d /var/lib/mysql ]] && [[ -f /usr/bin/mysql ]]
    then
        ntc "mariadb @ $HOSTNAME"
        source $SC_INSTALL_DIR/modules/mariadb/libs/mariadblib.sh
        backup_mariadb
    fi
    
    if [[ -d /var/lib/mongodb ]]
    then
        ntc "mongodb @ $HOSTNAME"
        
        ##
        ##  The current mongodb build is bugged - https://bugzilla.redhat.com/show_bug.cgi?id=1537510
        ##
        ##  Failed: error dumping metadata: error running `listIndexes`. Collection: `admin.system.version` Err: Unknown element kind (0x13)
        ##
        
        #if [[ ! -f /usr/bin/mongodump ]]
        #then
        #    sc_install mongo-tools
        #fi
        rm -fr /root/mongodb-dump/*
        out_path="/root/mongodb-dump/$(date +%Y_%m_%d__%H_%M_%S)"
        mkdir -p "$out_path"
        $SC_INSTALL_DIR/modules/backupdb/bin/mongodump --out "$out_path"
        
    fi
    
    
};
