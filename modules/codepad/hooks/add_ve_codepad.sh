#!/bin/bash

##
##   codepad add_ve_codepad hook — sourced by run_hook "add_ve_$T" from
##   the generic 'add-ve NAME codepad' command (containers module).
##   Initializes the codepad project in the freshly created container:
##   SSH keys, uid-shifted ownership, users/boilerplate symlinks.
##

init_codepad_project "$ARG"
