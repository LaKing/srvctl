#!/bin/bash

## reset_modules — drop the cached SC_USE_* module flags so they get
## re-evaluated on the next run.
## FIXME(v4): dead and incomplete — never called from anywhere in the repo,
## and it misses /root/.srvctl/modules.conf, the cache root actually uses.
function reset_modules() {
    msg "reset modules"
    rm -fr /var/local/srvctl/modules.conf

    rm -fr /home/*/.srvctl/modules.conf

}
