#!/bin/bash

## @@@ rebuild-ve VE [check|rollback|discard-old]
## @en Rebuild a container on the current fedora base image, keeping its site and databases
## &en Backs up the web root, homes, crontabs, site httpd configs, users and logical database dumps
## &en inside the running old container, stops it, keeps its tree as /srv/VE/exrootfs, builds a fresh
## &en rootfs and restores into it (the backup stays in /srv/backup inside), then checks services
## &en and the front page against the one saved before. For WordPress, PHP and static sites.
## &en A rerun continues at the phase that failed. 'check' repeats the check, 'rollback' puts the old
## &en tree back, 'discard-old' deletes it after a passed check. Log: /srv/VE/rebuild/rebuild.log

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/rebuild-ve.sh — entry of the rebuild; the phases are
##   in libs/rebuildlib.sh, the in-container halves in lib/rebuild-ve-*.sh.
##   Every run is appended to /srv/VE/rebuild/rebuild.log.
##

argument container-name
root_only

C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }
[[ -d /srv/$C ]] || { err "$C is not on this host"; exit 22; }

mkdir -p "/srv/$C/rebuild"
echo "## $NOW sc rebuild-ve $OPAS" >> "/srv/$C/rebuild/rebuild.log"
rebuild_ve "$C" "$OPA" 2>&1 | tee -a "/srv/$C/rebuild/rebuild.log"
exit_code="${PIPESTATUS[0]}"
((exit_code == 0)) || exit "$exit_code"
