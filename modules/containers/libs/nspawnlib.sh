#!/bin/bash

function create_nspawn_container_settings {
    
    
    
    local C
    C="$1"
    br="$2"
    if [[ -z $br ]]
    then
        br="$(get container "$C" br)" || exit
    fi
    uid="$(get container "$C" uid)"
    
    msg "Create nspawn container settings for $C $br ($uid)"
    
cat > "/srv/$C/$C.nspawn" << EOF
[Network]
Bridge=$br

[Exec]
PrivateUsers=$uid

[Files]
PrivateUsersChown=true
BindReadOnly=$SC_INSTALL_DIR
BindReadOnly=/var/srvctl3/share/containers/$C
BindReadOnly=/var/srvctl3/share/common
EOF
    
    mkdir -p "/var/srvctl3/share/containers/$C/users"
    
}
