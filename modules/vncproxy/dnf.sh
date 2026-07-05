#!/bin/bash

## Install host packages for the vncproxy module (sqlite for start.sh and
## for building the vendored proxy). Manual step, not run by any hook.
## FIXME(v4): does not install nmap (needed by vncproxy-restarter.sh), nor
## the python / C++ toolchain / rsync needed by build.sh.

sudo dnf -y install sqlite sqlite-devel sqlite-tcl
