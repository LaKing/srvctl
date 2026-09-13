#!/bin/bash

## @@@ remove-comount NAME CONTAINER
## @en Remove a container's shared mount, keeping the source files.
## &en Remove the datastore setting and generated mount configuration. Restart the target if running.

[[ $SRVCTL ]] || exit 4
root_only
hs_only
argument comount-name
[[ $OPA ]] || { err "Missing container"; exit 32; }

remove_comount "$OPA" "$ARG"
exif "Could not remove comount $ARG from $OPA"
