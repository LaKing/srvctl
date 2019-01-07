#!/bin/bash

## @@@ fix-sshd
## @en Fixing sshd permissions on keyfiles.
## &en A temporary script to fix sshd permissions on keyfiles.


run chown root:ssh_keys /etc/ssh/ssh_host_ecdsa_key
run chown root:ssh_keys /etc/ssh/ssh_host_ed25519_key
run chown root:ssh_keys /etc/ssh/ssh_host_rsa_key
run chmod 600 /etc/ssh/ssh_host_ecdsa_key
run chmod 600  /etc/ssh/ssh_host_ed25519_key
run chmod 600 /etc/ssh/ssh_host_rsa_key

run systemctl restart sshd.service