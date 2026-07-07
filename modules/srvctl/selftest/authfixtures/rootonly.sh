#!/bin/bash
## authfixture: ROOT_ONLY class.
[[ $SRVCTL ]] || exit 4
root_only
run action-root
