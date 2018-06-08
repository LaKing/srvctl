#!/bin/bash

if [[ "$rootfs_name" == "mail" ]]
then
    firewalld_offline_add_service imap
    firewalld_offline_add_service imaps
    firewalld_offline_add_service pop3s
fi
