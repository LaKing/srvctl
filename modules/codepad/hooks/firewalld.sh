#!/bin/bash

##
##   codepad firewalld hook — sourced by run_hooks firewalld during
##   update-install (firewalld module). Opens the codepad ports in the
##   HOST firewall; the service names are persisted as
##   /etc/firewalld/services/{http9000,https9001}.xml and rechecked by
##   name, so they must not change.
##

## codepad
firewalld_add_service http9000 tcp 9000
firewalld_add_service https9001 tcp 9001
