#!/bin/bash

## @@@ list-ve-releases [tsv]
## @en List the OS release of every local container, with upgrade-planning facts
## &en One line per container under /srv, oldest release first: OS release, unit state, whether
## &en its DNS points here, last web request, last change under /var/www/html, /srv and /home,
## &en size, owner, a suggested class (dead? / simple / wordpress / custom) and detected apps.
## &en Read-only. 'tsv' prints tab-separated values, to collect the lists of several hosts.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/list-ve-releases.sh — survey for the container OS upgrade.
##
##   The work is in lib/ve-releases.mjs. Root only: it reads every rootfs.
##   SC_HOST_IP comes from the sourced host.conf and is not exported, so it is
##   passed explicitly; the dns column compares the scanned A records with it.
##

root_only

SC_HOST_IP="$SC_HOST_IP" SC_DATASTORE_DIR="$SC_DATASTORE_DIR" /bin/node "$SC_INSTALL_DIR/modules/containers/lib/ve-releases.mjs" "$ARG"
exif "list-ve-releases failed"
