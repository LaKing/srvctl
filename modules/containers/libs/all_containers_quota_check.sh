#!/bin/bash

##
##   containers/libs/all_containers_quota_check.sh — hourly disk quota
##   enforcement.
##
##   Called from hooks/regenerate.sh only for the '#cron.hourly' ARG.
##   Records each local container's du (KB) in the datastore and
##   stops+disables containers exceeding their 'quota' key (datastore
##   default 250000000 KB).
##

## FIXME(v4): dead — nothing reads SIZE_LIMIT; it duplicates the
## datastore's quota default.
SIZE_LIMIT=250000000;

function all_containers_quota_check() {
    local list size quota

    if $SC_UID0
    then
        list="$(get cluster container_list)" || exit 15
    else
        list="$(cfg user container_list)" || exit 15
    fi

    for C in $list
    do
        if [[ -d /srv/$C ]]
        then
        	size="$(du -s /srv/"$C" | awk '{print $1;}')"

            msg "$C $size"

            put container "$C" du "$size"

            quota="$(get container "$C" quota)"

            ## FIXME(v4): if the quota lookup fails, quota is empty and the
            ## arithmetic compares size against 0 — a healthy container
            ## with a broken record gets stopped and disabled.
            if (( size > quota ))
            then
            	ntc "STOPPING $C SIZE $size IS OVER $quota"

                systemctl disable "srvctl-nspawn@$C" --no-pager
                systemctl stop "srvctl-nspawn@$C" --no-pager

            fi

        fi

    done
}
