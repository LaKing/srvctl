#!/bin/bash
##
## Usage:
## myvar="$(get container mydomain.ve ip)" || exit
## echo "Returned: $myvar"
##
##

function new {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node $SC_INSTALL_DIR/modules/datastore/main.js new $* 2>&1)"
    exif "DATASTORE-ERROR new $* EXIT ($?) $__result"
    
    datastore_push "new $*"
}

function get {
    
    local __result __exitcode
    
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" get $* 2>&1)"
    __exitcode="$?"
    
    ## missing otional values signal error 100
    ## return 0 on a value, 100 on a non found optional value
    
    if [[ $__exitcode == 0 ]]
    then
        echo "$__result"
        return $__exitcode
    fi
    
    if [[ $__exitcode == 100 ]]
    then
        if [[ $CMD == 'exec-function' ]] || [[ $CMD == 'get' ]]
        then
            err "DATASTORE get $* EXIT ($__exitcode) requested value is not defined. $__result"
        fi
        return $__exitcode
    fi
    
    err "DATASTORE-ERROR get $* EXIT ($__exitcode) $__result"
    return $__exitcode
}

function put {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" put $* 2>&1)"
    exif "DATASTORE-ERROR put $* EXIT ($?) $__result"
    
    datastore_push "put $*"
}

function out {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" out $* 2>&1)"
    exif "DATASTORE-ERROR out $* EXIT ($?) $__result"
    
    echo "$__result"
}

function cfg {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" cfg $* 2>&1)"
    exif "DATASTORE-ERROR cfg $* EXIT ($?) $__result"
    
    echo "$__result"
}

function del {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" del $* 2>&1
    exif "DATASTORE-ERROR del $* EXIT ($?) $__result"
    
    datastore_push "del $*"
}

## function internal execution
function fix {
    
    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" fix $* 2>&1
    exif "DATASTORE-ERROR fix $* EXIT ($?) $__result"
    
    datastore_push "del $*"
}
