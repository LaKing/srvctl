#!/bin/bash
## @en Root-only fixture command.
## &en Only root may run this one (permission-marker coverage).
[[ $SRVCTL ]] || exit 10
root_only

echo "secret"
