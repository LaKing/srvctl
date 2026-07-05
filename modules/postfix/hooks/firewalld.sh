#!/bin/bash

##
##   modules/postfix/hooks/firewalld.sh — open the mail ports on the host.
##
##   Runs via 'run_hooks firewalld' from the firewalld module's
##   update-install hooks. Enables the built-in smtp (25/tcp) and smtps
##   (465/tcp) services in the host's default firewalld zone
##   (firewalld_add_service, modules/firewalld/libs/firewalldlib.sh).
##

firewalld_add_service smtp
firewalld_add_service smtps
