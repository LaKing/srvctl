#!/bin/bash

###
###        MariaDB related client-functions
###

## this file my be sourced from other modules #backupdb
if ! [[ $SC_MARIADB_DUMP_CONF ]]
then
    SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
fi

function setup_mariadb {
    ## Main purpose of this function is to set up mysql
    msg "Setup mariadb"
    #if systemctl is-active mariadb.service
    #then
    
    ## TODO connection check
    #msg "Install Mysql/MariaDB."
    sc_install mariadb-server
    add_service mariadb
    
    #fi
}

function check_mariadb_connection {
    
    if [[ -f $SC_MARIADB_DUMP_CONF ]]
    then
        msg "Found $SC_MARIADB_DUMP_CONF"
        SC_MDA="--defaults-file=$SC_MARIADB_DUMP_CONF"
    else
        msg "Mariadb $SC_MARIADB_DUMP_CONF not found"
        SC_MDA="-u root"
    fi
    
    if run "/usr/bin/mysql $SC_MDA -e status" 2> /dev/null
    then
        msg ".. mysql connected"
    else
        err "CONNECTION FAILED. /usr/bin/mysql $SC_MDA -e status"
        exit
    fi
}


function backup_mariadb() {
    #local succ
    
    check_mariadb_connection
    
    log "Creating backup of Mysql/Mariadb databases with mysql $SC_MDA"
    
    rm -fr /root/mariadb-dump/* 2> /dev/null
    
    BACKUP_POINT="/root/mariadb-dump/$(date +%Y_%m_%d__%H_%M_%S)"
    mkdir -p "$BACKUP_POINT"
    
    msg "databases:"
    # shellcheck disable=SC2086
    echo "show databases" | mysql $SC_MDA
    
    ## All Databases into a single file?
    #mysqldump $MDA --all-databases >$BACKUP_POINT/all-databases.sql
    
    ## create backup for each database
    # shellcheck disable=SC2086
    for i in $(echo "show databases" | mysql $SC_MDA | grep -v Database); do
        if [ "$i" != "information_schema" ] && [ "$i" != "performance_schema" ]
        then
            nur "mysqldump $SC_MDA --databases $i > $BACKUP_POINT/$i.sql"
            # shellcheck disable=SC2086
            mysqldump $SC_MDA --databases "$i" > "$BACKUP_POINT/$i.sql"
            exif
        fi
    done
    
    
    msg "All databases have a backup in $BACKUP_POINT"
}

## PROCEDURE Add new database
function add_mariadb_db {
    
    local query f
    
    check_mariadb_connection
    
    ## input $dbd database-definition - basically the database name.
    ## $SC_MDA MaridaDB / MysqlDatabase - Argument
    
    if [ -z "$1" ]
    then
        dbd="$HOSTNAME"
    else
        dbd="$1"
    fi
    
    dbd=$(echo "$dbd" | tr '.' '_' | tr '-' '_')
    
    db_usr="${dbd:0:15}"
    db_name="${dbd:0:63}"
    
    if [[ -f /etc/mariadb-$db_name.conf ]]
    then
        db_pass="$(grep 'pwd:' /etc/mariadb-"$db_name".conf )"
        db_pwd="${db_pass:4}"
        ntc "Mariadb conf found for $db_name. ($db_pwd)"
        return
    fi
    
    db_pwd="$(get_password)"
    msg "Adding DB $dbd"
    
    query="CREATE DATABASE IF NOT EXISTS $db_name;"
    ntc "mysql $SC_MDA -e $query"
    # shellcheck disable=SC2086
    mysql $SC_MDA -e "$query"
    exif 'ERROR in mariadb query.'
    
    query="GRANT ALL ON $db_name.* TO '$db_usr'@'localhost' IDENTIFIED BY '$db_pwd'; flush privileges;"
    ntc "mysql $SC_MDA -e $query"
    # shellcheck disable=SC2086
    mysql $SC_MDA -e "$query"
    exif 'ERROR in mariadb query.'
    
    ## save these params to etc
    f="/etc/mariadb-$db_name.conf"
    echo "dbf:$db_name" > "$f"
    echo "usr:$db_usr" >> "$f"
    echo "pwd:$db_pwd" >> "$f"
    
    msg "Added MariaDB database $db_name user: $db_usr password: $db_pwd - saved in /etc/mariadb-$db_name.conf"
}

function secure_mariadb {
    
    #setup_mariadb
    check_mariadb_connection
    
    if [ -f "$SC_MARIADB_DUMP_CONF" ]
    then
        msg "mysql dump file found $SC_MARIADB_DUMP_CONF"
        cat "$SC_MARIADB_DUMP_CONF"
    else
        
        msg "Secure mariadb with a root password with mysql $SC_MDA"
        
        password="$(get_password)"
        
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DELETE FROM mysql.user WHERE User='';"
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
        # shellcheck disable=SC2086
        mysql $SC_MDA -e "DROP DATABASE IF EXISTS test;"
        
        query="UPDATE mysql.user SET Password=PASSWORD('$password') WHERE User='root'; flush privileges;"
        
        
        # shellcheck disable=SC2086
        if mysql $SC_MDA -e "$query"
        then
            log "Set database root password to: $password"
            
            ## set up backup params
            {
                echo '[client]'
                echo 'user=root'
                # shellcheck disable=SC2154
                echo "password=$password"
            } >> "$SC_MARIADB_DUMP_CONF"
            
        else
            err "CONNECTION FAILED. Could not set mariadb password, ..."
        fi
    fi
    
}

function mysql_root {
    check_mariadb_connection
    if [[ $1 ]]
    then
        # shellcheck disable=SC2086
        mysql $SC_MDA -e $1
    else
        # shellcheck disable=SC2086
        mysql $SC_MDA
    fi
}

return

## these are outdated from sc2



function secure_mariadb {
    
    setup_mariadb
    check_mariadb_connection
    
    ## Decide if mysql is secured, and has a defaults-file
    if [ -f "$SC_MARIADB_DUMP_CONF" ]
    then
        SC_MDA="--defaults-file=$SC_MARIADB_DUMP_CONF -u root"
        
        ## check_mariadb_connection
        
        if mysql "$SC_MDA" -e exit 2> /dev/null
        then
            err 'CONNECTION FAILED using '$SC_MARIADB_DUMP_CONF
            SC_MDA="-u root"
            
            if mysql "$SC_MDA" -e exit 2> /dev/null
            then
                err "CONNECTED without password, and not with $SC_MARIADB_DUMP_CONF"
            else
                err 'CONNECTION FAILED without password'
            fi
            
        else
            msg "CONNECTION to mysql is OK"
        fi
        
        
        
    else
        
        SC_MDA="-u root"
        
        
        if ! mysql "$SC_MDA" -e exit 2> /dev/null
        then
            msg 'CONNECTED to mysql / mariadb - securing.'
            
            get_password
            
            ## set up backup params
            {
                echo '[client]'
                echo 'user=root'
                # shellcheck disable=SC2154
                echo "password=$password"
            } >> "$SC_MARIADB_DUMP_CONF"
            
            mysql "$SC_MDA" -e "DELETE FROM mysql.user WHERE User='';"
            mysql "$SC_MDA" -e "DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');"
            mysql "$SC_MDA" -e "DROP DATABASE IF EXISTS test;"
            
            query="UPDATE mysql.user SET Password=PASSWORD('$password') WHERE User='root'; flush privileges;"
            
            
            if mysql "$SC_MDA" -e "$query"
            then
                log "Set database root password to: $password"
            else
                err "CONNECTION FAILED. Could not set mariadb password, ..."
            fi
        else
            err "CONNECTION FAILED Could not secure mysql, could not connect as root."
        fi
    fi
}



