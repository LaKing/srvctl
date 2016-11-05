#!/bin/bash

## @en First-aid diagnoistic command.

## &en Set of troubleshooting commands, that include information about:
## &en
## &en     srvctl version and variables
## &en     uptime
## &en     system/kernel version
## &en     boot configs
## &en     inactive services listed in srvctl
## &en     postfix fatal errors since yesterday
## &en     the mail que
## &en     firewall settings
## &en     table of processes
## &en     connected shell users
## &en
## &en Notes
## &en     To flush the mail que, use: postqueue -f
## &en     To remove all mail from the mail que use: postsuper -d ALL

## run only with srvctl
[[ $SRVCTL ]] || exit 4

msg "srvctl version $(cat "$SC_INSTALL_DIR/version")"

( set -o posix ; set ) | egrep "DEBUG=|ARG=|CMD=|OPA=|SC_"

# printenv

echo " -- Uptime: $(uptime)"
run uname -a
run sestatus

if [[ -f /usr/bin/grub2-editenv ]] && [[ -f /boot/grub2/grub.cfg ]]
then
    msg "-- Kernel --"
    run uname -r
    msg "Booting"
    run grub2-editenv list
    msg "Available for boot"
    run grep ^menuentry /boot/grub2/grub.cfg | cut -d "'" -f2
fi

msg "-- systemd - services --"
for service in /etc/systemd/system/multi-user.target.wants/*
do
    [[ -f $service ]] || continue
    service="$(basename "$service")"
    
    if ! systemctl is-active "$service" > /dev/null
    then
        run systemctl status "$service" --no-pager
    else
        msg "$service $(systemctl is-active "$service")"
    fi
done

msg "-- mail que --"
run journalctl -u postfix --since yesterday | grep fatal
run postqueue -p

if [[ -f /usr/sbin/firewalld ]]
then
    local zone
    zone=$(firewall-cmd --get-default-zone)
    msg "-- Firewall $(firewall-cmd --state) - default zone: $zone"
    run firewall-cmd --zone="$zone" --list-services
    echo ''
    
    msg "Interfaces:"
    run firewall-cmd --list-interfaces
    echo ''
fi

msg "-- table of processes --"
run top -n 1
msg "-- shell users --"
run w
msg "-- process tree --"
run systemctl status --no-pager

run_hooks diagnose





