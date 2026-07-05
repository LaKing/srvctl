#! /bin/bash

## modules/nfs/module-condition.sh
## Module condition for the nfs module, evaluated at init in a subshell;
## the value echoed on stdout is cached in modules.conf as SC_USE_NFS.
## Delegates by sourcing the containers module's condition verbatim, so
## nfs is enabled exactly when containers is — every cluster host gets the
## /srv export and the mesh mounts; there is no independent opt-out. This
## works only because conditions run in subshells (commonlib.sh): the
## sourced file's readonly SC_VIRT cannot clash with the parent shell.

# shellcheck source=/usr/local/share/srvctl/modules/containers/module-condition.sh
# shellcheck disable=SC1091 # runtime-path
source "$SC_INSTALL_DIR/modules/containers/module-condition.sh"
