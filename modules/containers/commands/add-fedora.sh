#!/bin/bash

## @@@ add-fedora  NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

argument container-name
authorize
sudomize


if [[ "${ARG:0:5}" == "mail." ]]
then
    msg "Adding mail container."
    C="$ARG"
    add_ve fedora "$C"
else
    add_ve fedora "$ARG"
fi

run_hook add-ve
run_hook regenerate


