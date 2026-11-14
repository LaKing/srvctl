#!/bin/bash

##
##   srvctl/libs/retiredlib.sh — what removed modules left on the hosts.
##
##   A module that is deleted from the repository can no longer clean up after
##   itself, so its host-side artifacts are listed here and the prune hook
##   (hooks/prune.sh, run by every regenerate) removes them. Removing a module
##   means adding its units and paths to these lists in the same change. An
##   entry stays for good: a host may run this version years after the removal.
##

## Unit files in /etc/systemd/system: disabled, stopped and deleted.
SC_RETIRED_UNITS="srvctl-gui.service"

## Files and directories, deleted with their content.
SC_RETIRED_PATHS="/etc/srvctl-gui /var/local/srvctl/commands.spec"

## Directories deleted only when empty, deepest first: they could hold data.
SC_RETIRED_EMPTY_DIRS="/var/srvctl3/gluster/srvctl-data /var/srvctl3/gluster/srvctl-storage /var/srvctl3/gluster"

## TEST SEAM for the selftest, not supported configuration.
: "${SC_RETIRED_UNIT_DIR:=/etc/systemd/system}"

function prune_retired {
    local unit path dir

    for unit in $SC_RETIRED_UNITS
    do
        [[ -e $SC_RETIRED_UNIT_DIR/$unit || -L $SC_RETIRED_UNIT_DIR/$unit ]] || continue
        if [[ ${SC_PRUNE_DRY_RUN:-false} != true ]]
        then
            ## disable removes the unit's links from the *.wants directories
            systemctl disable --now "$unit" > /dev/null 2>&1
            systemctl reset-failed "$unit" > /dev/null 2>&1
        fi
        prune "$SC_RETIRED_UNIT_DIR/$unit"
    done

    for path in $SC_RETIRED_PATHS
    do
        prune "$path"
    done

    for dir in $SC_RETIRED_EMPTY_DIRS
    do
        [[ -d $dir && ! -L $dir ]] || continue
        [[ -z $(ls -A "$dir") ]] || continue
        prune "$dir"
    done
}
