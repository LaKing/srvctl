#!/bin/bash

## MYSQL / MARIADB conf file that stores the mysql root password - in containers

if [[ -f /etc/mysqldump.conf ]]
then
    ## not unused, used later
    # shellcheck disable=SC2034
    SC_MARIADB_DUMP_CONF=/etc/mysqldump.conf
fi
