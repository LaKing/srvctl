#!/bin/bash
# shellcheck disable=SC2154
if [[ "$rootfs_name" == "mail" ]]
then
    firewalld_offline_add_service smtp
    firewalld_offline_add_service smtps
fi
