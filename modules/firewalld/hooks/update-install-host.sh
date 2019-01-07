#!/bin/bash

if [[ ! -f /usr/sbin/firewalld ]]
then
    sc_install firewalld
fi

run systemctl enable firewalld
run systemctl start firewalld
run systemctl status firewalld --no-pager

run_hooks firewalld

if [[ "$(firewall-cmd --query-masquerade --permanent)" != yes ]]
then
    run firewall-cmd --add-masquerade --permanent
fi

if [[ "$(firewall-cmd --query-masquerade)" != yes ]]
then
    run firewall-cmd --add-masquerade
fi
