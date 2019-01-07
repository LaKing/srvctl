#!/bin/bash

# shellcheck disable=SC2048
# shellcheck disable=SC2154
if [[ "$rootfs_name" == codepad ]]
then
    
    ## apply same as /modules/firewalld/hooks/mkrootfs_fedora.sh
    
    ## global http and https
    firewalld_offline_add_service http tcp 80
    firewalld_offline_add_service https tcp 443
    
    ## additional http and https
    firewalld_offline_add_service http8080 tcp 8080
    firewalld_offline_add_service https8443 tcp 8443
    
    ## elasticsearch
    firewalld_offline_add_service https9200 tcp 9200
    
    ## apply codepad extras
    firewalld_offline_add_service https9000 tcp 9000
    firewalld_offline_add_service https9001 tcp 9001
fi