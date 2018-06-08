#!/bin/bash

## import certificates from root's folder to the system

[[ $SRVCTL ]] || exit 4


install_acme
