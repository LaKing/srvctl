#!/bin/bash

##
##   modules/named/hooks/version.sh — report the installed BIND version.
##
##   Runs via 'run_hooks version' from 'sc version'. msg_version_installed
##   (modules/srvctl) prints the bind package version, or a notice that
##   bind is not installed.
##

msg_version_installed bind
