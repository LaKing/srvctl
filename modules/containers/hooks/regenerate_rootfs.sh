#!/bin/bash

mkrootfs_fedora_base fedora "systemd-container httpd mod_ssl"
mkrootfs_fedora_base mail  "dovecot"
