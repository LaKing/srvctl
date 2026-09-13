#!/bin/bash
[[ $SRVCTL ]] || exit 4

sc_install util-linux
exif "Could not install mount tools"
regenerate_comounts
