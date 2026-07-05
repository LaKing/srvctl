#!/bin/bash

##
##   modules/datastore/libs/bashlib.sh — the datastore verb API.
##
##   Defines the bash wrappers new/get/put/out/cfg/del/add used by nearly
##   every module (~159 call sites farm-wide). Each call spawns a fresh
##   /bin/node process running main.js; the arguments are word-split on
##   purpose (SC2048/SC2086 disabled) because callers pass unquoted
##   argument lists throughout the codebase.
##
##   Exit-code contract, relied upon by callers — do not change:
##     0     success; get/out/cfg echo the node output
##     100   get: requested optional value is not defined
##     other error; exif aborts the run for the mutating verbs
##
##   The mutating verbs new/put/del git-commit the json change via
##   datastore_push (libs/gitlib.sh).
##
##   Usage:
##     myvar="$(get container mydomain.ve ip)" || exit
##     echo "Returned: $myvar"
##

## create a record: new container|user|reseller ARG [TYPE] [BRIDGE]
function new {

    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" new $* 2>&1)"
    exif "DATASTORE-ERROR new $* EXIT ($?) $__result"

    datastore_push "new $*"
}

## read a value: get DAT ARG [OPA] — prints the value on stdout
function get {

    local __result __exitcode

    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" get $* 2>&1)"
    __exitcode="$?"

    ## missing optional values signal error 100
    ## return 0 on a value, 100 on a non found optional value

    if [[ $__exitcode == 0 ]]
    then
        echo "$__result"
        return $__exitcode
    fi

    if [[ $__exitcode == 100 ]]
    then
        ## only report the missing value when the user asked for it directly
        if [[ $CMD == 'exec-function' ]] || [[ $CMD == 'get' ]]
        then
            err "DATASTORE get $* EXIT ($__exitcode) requested value is not defined. $__result"
        fi
        return $__exitcode
    fi

    err "DATASTORE-ERROR get $* EXIT ($__exitcode) $__result"
    return $__exitcode
}

## write or delete a field: put DAT ARG OPA [VAL] — no VAL deletes the field,
## "true"/"false" are stored as booleans, everything else as string
function put {

    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" put $* 2>&1)"
    exif "DATASTORE-ERROR put $* EXIT ($?) $__result"

    datastore_push "put $*"
}

## dump a record as sourceable shell variables: out DAT ARG [json]
function out {

    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" out $* 2>&1)"
    exif "DATASTORE-ERROR out $* EXIT ($?) $__result"

    echo "$__result"
}

## run an internal mutating function: cfg container C update_ip|add_mapped_port ...
function cfg {

    local __result
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    __result="$(/bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" cfg $* 2>&1)"
    exif "DATASTORE-ERROR cfg $* EXIT ($?) $__result"

    echo "$__result"
}

## delete a record: del DAT ARG
function del {

    local __result
    ## FIXME(v4): __result is declared but never assigned (node output goes
    ## straight to stdout), so the exif diagnostic below always lacks the
    ## node error text that the other verbs capture via command substitution.
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" del $* 2>&1
    exif "DATASTORE-ERROR del $* EXIT ($?) $__result"

    datastore_push "del $*"
}

## append to an array field: add container C user|vncuser NAME
function add {

    local __result
    ## FIXME(v4): same as del — __result is never assigned, so the exif text
    ## lacks the node output and the trailing echo prints an empty line.
    # shellcheck disable=SC2048
    # shellcheck disable=SC2086
    /bin/node "$SC_INSTALL_DIR/modules/datastore/main.js" add $* 2>&1
    exif "DATASTORE-ERROR add $* EXIT ($?) $__result"

    echo "$__result"
}
