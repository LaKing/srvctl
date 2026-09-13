#!/bin/bash

## @@@ test-comount NAME CONTAINER
## @en Test the shared directory as root and, for codepad shares, codepad inside a running container.
## &en Create, read, append to and delete a temporary directory and file through the shared mount.

[[ $SRVCTL ]] || exit 4
root_only
hs_only
argument comount-name
[[ $OPA ]] || { err "Missing container"; exit 32; }

test_comount "$OPA" "$ARG"
exif "Comount $ARG write test failed for $OPA"
