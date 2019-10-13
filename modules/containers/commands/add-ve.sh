#!/bin/bash

## @@@ add-ve NAME
## @en Add a standard fedora container, alias of add-fedora
## &en Generic container for customization.
## &en This command is an alias for add-fedora.

if [[ -f /usr/local/share/srvctl/modules/containers/commands/add-fedora.sh ]]
then
    msg "Adding a standard fedora container"
    source /usr/local/share/srvctl/modules/containers/commands/add-fedora.sh
else
    err "could not locate add-fedora command"
fi
