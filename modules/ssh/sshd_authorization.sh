#!/bin/bash

_user="$1"

## used by root as root
cat "/var/srvctl3/share/common/authorized_keys" 2> /dev/null

## used on the host, for host-to-host authentication
cat "/var/srvctl3/gluster/srvctl-data/users/$_user"/*.pub 2> /dev/null

## used in containers for user as root
cat "/var/srvctl3/share/containers/$HOSTNAME"/users/*/*.pub 2> /dev/null

exit 0