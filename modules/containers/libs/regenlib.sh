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
    cfg system postfix_relaydomains > /etc/postfix/relaydomains
}

function regenerate_ssh_config() {
    cfg system ssh_config > /etc/ssh/ssh_config.d/srvctl-containers.conf
}


