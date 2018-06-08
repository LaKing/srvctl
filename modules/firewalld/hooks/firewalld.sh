#!/bin/bash

## these are global



msg "Firewalld on $HOSTNAME"

if [[ "${HOSTNAME:0:5}" == "mail." ]]
then
    firewalld_add_service imap
    firewalld_add_service imaps
    firewalld_add_service pop3s
    firewalld_add_service smtp
    firewalld_add_service smtps
else
    ## global http and https
    firewalld_add_service http tcp 80
    firewalld_add_service https tcp 443
    
    ## additional http and https
    firewalld_add_service http8080 tcp 8080
    firewalld_add_service https8443 tcp 8443
    
    ## elasticsearch
    firewalld_add_service https9200 tcp 9200
fi

