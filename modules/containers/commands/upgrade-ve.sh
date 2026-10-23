#!/bin/bash

## @@@ upgrade-ve VE [check|rollback|discard-old]
## @en Upgrade a container's Fedora in place to the release of the current base image
## &en Copies the whole tree to /srv/VE/exrootfs, then runs dnf distro-sync in a throwaway
## &en nspawn of the stopped container (inside the running one rpm cannot replace systemd),
## &en puts back enabled units the upgrade dropped, starts it and checks the release, the
## &en services that ran before and the front page. At most 2 releases at once; for older ones
## &en or a fresh start use rebuild-ve. A rerun continues at the phase that failed. 'check'
## &en repeats the check, 'rollback' puts the copy back, 'discard-old' deletes it after a passed
## &en check. Log: /srv/VE/upgrade/upgrade.log

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/upgrade-ve.sh — entry of the in-place upgrade; the
##   phases are in libs/upgradelib.sh. Every run is appended to
##   /srv/VE/upgrade/upgrade.log.
##

argument container-name
root_only

C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }
[[ -d /srv/$C ]] || { err "$C is not on this host"; exit 22; }

mkdir -p "/srv/$C/upgrade"
echo "## $NOW sc upgrade-ve $OPAS" >> "/srv/$C/upgrade/upgrade.log"
upgrade_ve "$C" "$OPA" 2>&1 | tee -a "/srv/$C/upgrade/upgrade.log"
exit_code="${PIPESTATUS[0]}"
((exit_code == 0)) || exit "$exit_code"
