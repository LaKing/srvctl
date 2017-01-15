#!/bin/bash

function create_nspawn_container_settings {
    local C bridge
    C="$1"
    bridge="$2"
    
cat > "/srv/$C/$C.nspawn" << EOF
[Network]
Bridge=$bridge

[Exec]
PrivateUsers=pick

[Files]
PrivateUsersChown=true
BindReadOnly=$SC_INSTALL_DIR

EOF
    
}
