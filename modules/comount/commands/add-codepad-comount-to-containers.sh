#!/bin/bash

## @@@ add-codepad-comount-to-containers PATH CONTAINER...
## @en Share a managed directory as codepad in containers.
## &en PATH is the container path; storage is /var/srvctl3/comount/as-codepad followed by PATH.
## &en Assign source files to codepad with owner read/write access. Running targets are restarted.

[[ $SRVCTL ]] || exit 4
root_only
hs_only
argument path

add_comount_to_containers codepad "$ARG" "${SC_ARGV[@]:2}"
exif "Could not add comount"
