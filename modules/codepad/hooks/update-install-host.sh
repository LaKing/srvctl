#!/bin/bash

##
##   codepad update-install-host hook — sourced by run_hooks
##   update-install-host from 'sc update-install'. Installs gcc-c++ on
##   the HOST so native node-module builds for codepad projects work.
##

run dnf -y install gcc-c++
