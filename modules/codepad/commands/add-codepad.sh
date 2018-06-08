#!/bin/bash

## @@@ add-codepad NAME
## @en Add a codepad fedora container.
## &en Generic container for software developmen.
## &en Contains all packages for collaborative software development.

ve_only

if [[ "${ARG:0:5}" == "mail." ]]
then
    err "Adding codepad as mail container is not permitted."
fi

argument container-name
authorize
sudomize

add_ve codepad "$ARG"

run_hook add-ve
run_hook regenerate

init_codepad_project "$ARG"

