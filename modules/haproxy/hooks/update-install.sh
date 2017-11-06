#!/bin/bash

## HAproxy is a reverse Proxy for http / https

msg "Installing HAproxy as the reverse proxy"

sc_install haproxy

mkdir -p /var/haproxy

firewalld_add_service http tcp 80
firewalld_add_service https tcp 443
