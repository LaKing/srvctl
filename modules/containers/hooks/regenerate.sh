#!/bin/bash

##
##   containers/hooks/regenerate.sh — reconcile /srv with the datastore.
##
##   Runs via 'run_hook regenerate' ('sc regenerate', after add/remove
##   commands, and hourly from cron). All functions from
##   libs/regenlib.sh: import stray /srv containers into the database and
##   re-enable their units, create locally-missing containers assigned to
##   this host, repair ownership, and rewrite /etc/hosts. The literal
##   '#cron.hourly' ARG (matching the installed cron script exactly)
##   additionally enforces disk quotas.
##

check_container_directories
check_container_database
check_container_ownership

regenerate_etc_hosts

## temporary measure while i figure out why this is not applied on boot.
## https://github.com/systemd/systemd/issues/17992
sysctl fs.inotify.max_user_watches=16777216

if [[ $ARG == "#cron.hourly" ]]
then
	all_containers_quota_check
fi