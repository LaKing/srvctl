#!/bin/bash

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