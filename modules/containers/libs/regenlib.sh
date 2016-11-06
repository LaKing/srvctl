#!/bin/bash

function regenerate() {
    regenerate_etc_hosts
    regenerate_etc_postfix_relaydomains
    regenerate_ssh_config
}

function regenerate_etc_hosts() {
    cfg system etc_hosts > /etc/hosts
}

function regenerate_etc_postfix_relaydomains() {
    if [[ -d /etc/postfix/ ]]
    then
        cfg system postfix_relaydomains > /etc/postfix/relaydomains
    fi
}

function regenerate_ssh_config() {
    cfg system ssh_config > /etc/ssh/ssh_config.d/srvctl-containers.conf
    cfg system host_keys  > /etc/ssh/ssh_known_hosts
}
