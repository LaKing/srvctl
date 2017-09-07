#!/bin/bash

## HAproxy is a reverse Proxy for http / https

msg "Installing HAproxy as the reverse proxy"

sc_install haproxy

mkdir -p /var/haproxy
