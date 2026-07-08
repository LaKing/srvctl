#!/bin/bash

## @@@ fix-sshd
## @en Fixing sshd permissions on keyfiles.
## &en A temporary script to fix sshd permissions on keyfiles.

##
##   Maintenance command: restore ownership (root:ssh_keys) and mode (600)
##   on the three ssh host key files, then restart sshd.
##

## WP-E.2.b: host sshd maintenance -> root only.
root_only

run chown root:ssh_keys /etc/ssh/ssh_host_ecdsa_key
run chown root:ssh_keys /etc/ssh/ssh_host_ed25519_key
run chown root:ssh_keys /etc/ssh/ssh_host_rsa_key
run chmod 600 /etc/ssh/ssh_host_ecdsa_key
run chmod 600 /etc/ssh/ssh_host_ed25519_key
run chmod 600 /etc/ssh/ssh_host_rsa_key

run systemctl restart sshd.service