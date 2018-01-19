#!/bin/bash

## @@@ add-fedora  NAME
## @en Add a fedora container.
## &en Generic container for customization.
## &en Contains basic packages.

argument container-name
authorize
sudomize

add_ve fedora "$ARG"

run_hook add-ve
run_hook regenerate


