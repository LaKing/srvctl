#!/bin/bash

#if [[ ! /usr/sbin/firewalld ]]
#then
sc_install firewalld
#fi

run systemctl enable firewalld
run systemctl start firewalld
run systemctl status firewalld --no-pager

run_hooks firewalld
