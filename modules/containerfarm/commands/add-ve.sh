#!/bin/bash

## @@@ add-ve NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

argument container-name
sudomize
authorize

local C T
C="$ARG"
T="fedora"

if [[ "$(get container "$C" exist)" == true ]]
then
    err "$C already exists in the system! Exiting"
    exit 11
fi

## check for a mistake
if [[ -d /srv/$C ]]
then
    err "/srv/$C already exists! Exiting"
    exit 11
fi

## add to database
new container "$C" "$T" || exit


## make local container
create_nspawn_container_filesystem "$C" "$T"
create_nspawn_container_network "$C" "$T"

run systemctl start "$C" --no-pager
run systemctl status "$C" --no-pager

run_hook regenerate


