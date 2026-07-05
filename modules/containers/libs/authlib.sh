#!/bin/bash

##
##   containers/libs/authlib.sh — host-side / container-side guards.
##
##   hs_only and ve_only are called near the top of command files across
##   many modules (haproxy, named, saslauthd, usersonve, vncproxy, ...).
##   Their names double as literal marker strings: hint_on_file
##   (commonlib.sh) greps the first 20 lines of a command file for them
##   to filter the help listing — keep both the function names and the
##   in-file call positions stable.
##

## FIXME(v4): SC_ON_HS is never assigned anywhere in bash — with the
## variable unset, 'if $SC_ON_HS' expands to an empty command list
## (status 0), so the guard ALWAYS passes and the exit 44 branch is
## dead. Enforcement today comes only from the help-listing grep and
## module activation conditions. Same for SC_ON_VE below.
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
