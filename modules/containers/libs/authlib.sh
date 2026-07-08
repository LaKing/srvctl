#!/bin/bash

##
##   containers/libs/authlib.sh — context guards MOVED to srvctl authlib.
##
##   hs_only and ve_only now live in modules/srvctl/libs/authlib.sh (WP-E
##   VE-side sweep). They were here, in the CONTAINERS module, which is INACTIVE
##   inside a container — so `ve_only` was undefined inside a VE, and every
##   usersonve command's ve_only call was a silent command-not-found no-op.
##   srvctl authlib is always loaded, so the definitions belong there.
##
##   This file is intentionally left as a pointer so the move is discoverable;
##   it defines nothing. If containers grows container-specific guards later,
##   they can live here again.
