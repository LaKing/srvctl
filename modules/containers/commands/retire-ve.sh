#!/bin/bash

## @@@ retire-ve VE [no-web]
## @en Back up a container and delete its files, keeping its domain as a domain-only record
## &en The container's files go (rootfs, nspawn files, /srv/VE), its record stays with the field
## &en domain_only=true, so the DNS zone, the web_ve routing, relaydomains and mail_ve routing,
## &en the certificate and the DKIM signing of the domain keep working.
## &en The tree is copied to the backup path first (SC_BACKUP_PATH/srvctl-containers/VE/DATE).
## &en The DKIM key is kept in $SC_DATASTORE_DIR/opendkim/VE/; the unit is stopped, disabled and masked.
## &en VE must have a web_ve (set-ve-web-ve VE WEBVE); 'no-web' accepts a domain without web.
## &en A missing mail_ve is reported. Refused for bridge containers, for a container whose ip
## &en belongs to another host's network, and while another VE hands its web or mail to VE.
## &en remove-ve VE or destroy-ve VE deletes the domain-only record.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

hs_only
root_only

argument container
existing_container "$ARG"

retire_ve_preflight "$ARG" "$OPA" || exit 22
retire_ve "$ARG"

## sourced context: leave the deleted working directory
cd /srv || return
