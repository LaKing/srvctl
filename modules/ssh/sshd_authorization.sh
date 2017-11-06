#!/bin/bash

_user="$1"

echo '###'
## used by root as root
cat "/var/srvctl3/share/common/authorized_keys" 2> /dev/null

echo '###'
## used on the host, for host-to-host authentication
cat "/var/srvctl3/gluster/srvctl-data/users/$_user"/*.pub 2> /dev/null
cat "/var/srvctl3/datastore/users/$_user"/*.pub 2> /dev/null

echo '###'
## used in containers for user as root
cat "/var/srvctl3/share/containers/$HOSTNAME"/users/*/*.pub 2> /dev/null

exit 0
