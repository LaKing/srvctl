#!/bin/bash

##
##   modules/ftp/hooks/firewalld.sh — open the FTP port on the host.
##
##   Fired (nested) by the firewalld module's update-install hooks during
##   "sc update-install". Adds the stock "ftp" service (TCP/21 plus the
##   FTP conntrack helper) permanently to firewalld's default zone via
##   firewalld_add_service (firewalld module lib); idempotent on rerun.
##

## FIXME(v4): plaintext-FTP port 21 is opened permanently on every
## container-farm host with no opt-out, for a daemon that is never started
## (see hooks/update-install-host.sh) — standing firewall exposure.
firewalld_add_service ftp
