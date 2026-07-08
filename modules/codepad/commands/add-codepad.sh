#!/bin/bash

## @@@ add-codepad NAME
## @en Add a fedora container with codepad preinstalled.
## &en Codepad container for software development.
## &en Contains the collaborative software development environment.


## DEPRECATED
##
##   Kept for compatibility; the canonical creation path is the generic
##   'add-ve NAME codepad', which reaches this module through the
##   add_ve_codepad hook. Note that only this command enforces the
##   *-devel name rule, which haproxy relies on to proxy the codepad
##   ports (9000/9001) to the container.
##
##   Creates the container from the codepad template rootfs via add_ve,
##   regenerates, then initializes the per-container codepad project
##   (fresh SSH keys, uid-shifted ownership, boilerplate symlinks).
##

if [[ "${ARG:0:5}" == "mail." ]]
then
    err "Adding codepad into a mail container is uncommon, and not suggested. I will stop for now."
    exit 13
fi

if [[ "${ARG: -6}" != "-devel" ]]
then
    err "We require codepad containers to use a *-devel name. Exiting for now."
    exit 13
fi

argument container-name
## WP-E.2.b: container provisioning -> operator/root (was authorize stub).
operators_only
sudomize

add_ve codepad "$ARG"

## no module ships an add-ve hook today; kept as a no-op extension point
run_hook add-ve
run_hook regenerate

init_codepad_project "$ARG"

## FIXME(v4): duplicate — init_codepad_project already runs this hook;
## any future add_codepad_project provider would execute twice per add.
run_hook add_codepad_project
