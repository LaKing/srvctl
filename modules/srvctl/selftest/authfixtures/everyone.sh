#!/bin/bash
## authfixture: EVERYONE class — no guard; any role may run it.
[[ $SRVCTL ]] || exit 4
run action-everyone
