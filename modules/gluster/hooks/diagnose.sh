#!/bin/bash

##
##   modules/gluster/hooks/diagnose.sh — gluster health printout.
##
##   Fired by "run_hooks diagnose" during "sc diagnose" (srvctl module).
##   Prints gluster peer and volume status; read-only, no side effects.
##   Never runs at this commit: the module is hard-disabled at baseline
##   (see module-condition.sh) and is a deprecation candidate for v4.
##

msg "Diagnose for gluster - the cloud filesystem."
run gluster peer status
run gluster volume status all
