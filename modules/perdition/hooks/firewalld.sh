#!/bin/bash

firewalld_add_service imaps
firewalld_add_service pop3s

if [[ "${container:0:5}" == "mail." ]]
then
    firewalld_add_service imap
fi
