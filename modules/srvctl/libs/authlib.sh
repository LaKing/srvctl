#!/bin/bash

##
##   authlib — who may run a command. Always loaded, on hosts and in containers.
##
##   The sudoers entry (srvctl.sh *) lets every account start srvctl at uid 0,
##   so uid 0 proves nothing. The caller is SC_USER (SUDO_USER when set, which
##   sudo itself fills in), and every guard decides by that name:
##
##     root_only          genuine root
##     operators_only     root, or a user whose record says role=operator
##     users_only         root, or a user with a record on this host
##     owner_only T ID    root, the owner of the record, or the owner's reseller
##
##   A guard is called on a line of its own, before any state change. That
##   line is also what the dispatcher looks for: a caller who came through
##   sudo may start only a command that has one (command_may_run, commonlib.sh),
##   and the help lists root_only and operators_only commands by role.
##   Exit codes callers rely on: 44 authorization failure, 32 missing argument.
##

## Genuine root: the name AND the uid. The name alone could be a USER=root
## spoof without privilege, the uid alone is anybody after sudo.
function sc_is_root {
    [[ $SC_USER == root ]] && $SC_UID0
}

function root_only {
    sc_is_root && return 0
    err "Authorization failure. (root_only)"
    exit 44
}

## Role cache. Set here, so a value inherited from the environment is never
## trusted; sc_role is the only writer.
SC_ROLE=
_SC_ROLE_RESOLVED=false

## Print the caller's role: root, operator or user. The role is read from this
## host's user record, so an operator here is a user on a host whose record
## does not say so. A missing role or a failed read is a user, never more.
function sc_role {
    local role
    if ! $_SC_ROLE_RESOLVED
    then
        SC_ROLE=user
        if sc_is_root
        then
            SC_ROLE=root
        elif role="$(get user "$SC_USER" role)" && [[ $role == operator ]]
        then
            SC_ROLE=operator
        fi
        _SC_ROLE_RESOLVED=true
    fi
    echo "$SC_ROLE"
}

function operators_only {
    case "$(sc_role)" in
        root | operator) return 0 ;;
    esac
    err "Operators only."
    exit 44
}

## For a command that acts for the caller himself: it creates what he will own
## or changes his own account. An account without a user record (a service
## account, a login that srvctl did not create) owns nothing here.
function users_only {
    sc_is_root && return 0

    local exists rc
    exists="$(get user "$SC_USER" exist)"
    rc=$?
    if [[ $rc != 0 ]]
    then
        err "Cannot verify the user $SC_USER: datastore lookup failed ($rc)"
        exit "$rc"
    fi
    [[ $exists == true ]] && return 0
    err "$SC_USER is not a user of this host."
    exit 44
}

## Root may act on every record. The owner (field user) and the owner's
## reseller are re-executed through sudo and pass here a second time at uid 0,
## still under their own name. Everybody else ends with 44.
##
## get returns 0 with a value, 100 for an unset field and anything else for a
## failed read. A failed read ends the command with that code: reporting it as
## "no access" would hide a datastore fault behind a denial.
function owner_only { ## type id
    sc_is_root && return 0

    local owner reseller rc
    owner="$(get "$1" "$2" user)"
    rc=$?
    if [[ $rc == 0 || $rc == 100 ]]
    then
        reseller="$(get "$1" "$2" reseller)"
        rc=$?
    fi
    if [[ $rc != 0 && $rc != 100 ]]
    then
        err "Cannot verify the owner of $2: datastore lookup failed ($rc)"
        exit "$rc"
    fi

    if [[ $SC_USER == "$owner" ]] || [[ $SC_USER == "$reseller" ]]
    then
        sudomize
        return 0
    fi

    err "$SC_USER has no access to $2"
    exit 44
}

function argument {
    if [[ -z $ARG ]]
    then
        err "Argument $1 missing."
        exit 32
    fi
}

## Re-execute the command line at uid 0 and end with its exit code. A no-op
## at uid 0. Call it only after the guard: it gives no permission by itself.
## SC_ARGV is the untouched argv of srvctl.sh, so arguments keep their spaces.
function sudomize {
    $SC_UID0 && return 0
    debug "@sudomize"
    sudo "$SC_INSTALL_DIR/srvctl.sh" "${SC_ARGV[@]}"
    exit $?
}

## Context markers. hint_on_file hides an hs_only command where SC_HOSTNET is
## unset (inside a container).
##
## FIXME(v4): SC_ON_HS / SC_ON_VE are never assigned, so `if $SC_ON_HS` runs
## an empty command (status 0) and both guards always pass. What keeps a host
## command out of a container is the module condition plus the identity guard.
function hs_only {
    if $SC_ON_HS
    then
        return 0
    else
        err "Authorization failure - this command is host-only"
        exit 44
    fi
}

function ve_only {
    if $SC_ON_VE
    then
        return 0
    else
        err "Authorization failure - this command is VE-only"
        exit 44
    fi
}
