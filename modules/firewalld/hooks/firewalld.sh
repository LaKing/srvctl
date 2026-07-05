#!/bin/bash

##
##   modules/firewalld/hooks/firewalld.sh — default open ports.
##
##   Custom hook point 'firewalld', invoked via 'run_hooks firewalld'
##   from this module's update-install-host.sh and update-install-ve.sh.
##   Other modules (codepad, ftp, perdition, postfix) contribute their
##   own hooks/firewalld.sh at the same point. Opens the srvctl default
##   set of web and mail ports in the default zone via
##   firewalld_add_service (libs/firewalldlib.sh).
##

msg "Firewalld on $HOSTNAME"

## mail services: opened globally, using the built-in firewalld
## definitions (no proto/port argument needed).
## FIXME(v4): mail ports and elasticsearch 9200 are opened on every
## managed host and container regardless of whether those services run
## there — move them to the modules that actually provide them.
firewalld_add_service imap
firewalld_add_service imaps
firewalld_add_service pop3s
firewalld_add_service smtp
firewalld_add_service smtps

## global http and https
firewalld_add_service http tcp 80
firewalld_add_service https tcp 443

## additional http and https
firewalld_add_service http8080 tcp 8080
firewalld_add_service https8443 tcp 8443

## elasticsearch
firewalld_add_service https9200 tcp 9200
