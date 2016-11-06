#!/bin/bash

## special services
# shellcheck disable=SC2154
if [[ $op == "enable" ]] && [[ -f "/etc/srvctl/containers/$service.service" ]] && $IS_ROOT
then
    run systemctl enable "/etc/srvctl/containers/$service.service"
    run systemctl start "$service.service"
    exit 0
fi
