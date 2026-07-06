#!/bin/bash
## @@@ harness-hostonly
## @en Container-host-only fixture command (hs_only filter coverage).
## &en Shown only when SC_HOSTNET is set.
[[ $SRVCTL ]] || exit 10
hs_only

echo "host-only"
