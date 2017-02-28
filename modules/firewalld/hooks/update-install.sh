#!/bin/bash

run systemctl enable firewalld
run systemctl start firewalld
run systemctl status firewalld --no-pager

if [[ "$(firewall-cmd --query-masquerade --permanent)" != yes ]]
then
    run firewall-cmd --add-masquerade --permanent
fi

if [[ "$(firewall-cmd --query-masquerade)" != yes ]]
then
    run firewall-cmd --add-masquerade
fi
