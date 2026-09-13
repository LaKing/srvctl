#!/bin/bash

##
##   codepad firewalld hook — sourced by run_hooks firewalld during
##   update-install (firewalld module). Opens the codepad ports in the
##   HOST firewall; the service names are persisted as
##   /etc/firewalld/services/{https9000,https9001,https9002}.xml and rechecked
##   by name, so they must not change.
##
##   All three are TLS ports: haproxy binds each of them 'ssl crt
##   /var/haproxy' (modules/haproxy/haproxy.js). 9000 was named 'http9000'
##   in earlier versions — a misnomer, and one that disagreed with the
##   template rootfs, which always registered it as 'https9000'. A host
##   installed before the rename keeps the stale http9000 service enabled
##   next to the new one; it opens the same port, so nothing breaks, but
##   drop it with:
##     zone="$(firewall-cmd --get-default-zone)"
##     firewall-cmd --zone="$zone" --permanent --remove-service=http9000
##     rm -f /etc/firewalld/services/http9000.xml
##     firewall-cmd --reload
##

## codepad
firewalld_add_service https9000 tcp 9000
firewalld_add_service https9001 tcp 9001
firewalld_add_service https9002 tcp 9002
