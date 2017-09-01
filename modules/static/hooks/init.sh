#!/bin/bash

if $SC_USE_GLUSTER
then
    gluster_mount_data srvctl-storage /var/srvctl3/storage
else
    mkdir -p /var/srvctl3/storage
fi

return 0
