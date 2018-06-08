#!/bin/bash

## these are global
if [[ "$rootfs_name" != "mail" ]]
then
    ## global http and https
    firewalld_offline_add_service http tcp 80
    firewalld_offline_add_service https tcp 443
    
    ## additional http and https
    firewalld_offline_add_service http8080 tcp 8080
    firewalld_offline_add_service https8443 tcp 8443
    
    ## elasticsearch
    firewalld_offline_add_service https9200 tcp 9200
else
    firewalld_offline_add_service imap tcp 143
    firewalld_offline_add_service imaps tcp 993
    firewalld_offline_add_service pop3s tcp 995
    firewalld_offline_add_service smtp tcp 25
    firewalld_offline_add_service smtps tcp 465
fi

