#!/bin/bash

function regenerate_etc_hosts() {
    # shellcheck disable=SC2094
    cfg system /etc/hosts > /etc/hosts
}

function regenerate_etc_postfix_relaydomains() {
    # shellcheck disable=SC2094
    cfg system /etc/postfix/relaydomains > /etc/postfix/relaydomains
}


