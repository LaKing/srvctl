#!/bin/bash

## @@@ add-codepad NAME
## @en Add a fedora container with codepad preinstalled.
## &en Codepad container for software development.
## &en Contains the collaborative software development environment.


## DEPRECATED

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
authorize
sudomize

add_ve codepad "$ARG"

run_hook add-ve
run_hook regenerate

init_codepad_project "$ARG"

run_hook add_codepad_project
