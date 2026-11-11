#!/bin/bash

##
##   containers/libs/all_containers_quota_check.sh — hourly disk quota
##   enforcement.
##
##   Called from hooks/regenerate.sh only for the '#cron.hourly' ARG.
##   Records each local container's rootfs du (KB) in the datastore and
##   stops+disables containers exceeding their 'quota' key (datastore
##   default 250000000 KB). Only /srv/$C/rootfs is measured: the rest of
##   /srv/$C holds host-side config, and host mounts such as comount's
##   /srv/$C/comount/NAME would otherwise count shared data per member.
##   rebuild-ve keeps its backup in /srv/$C/backup, outside the measure.
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
        if [[ -d /srv/$C/rootfs ]]
        then
        	size="$(du -s /srv/"$C"/rootfs | awk '{print $1;}')"

            msg "$C $size"

            put container "$C" du "$size"

            quota="$(get container "$C" quota)"

            ## a failed lookup would compare against 0 and stop a healthy container
            [[ $quota =~ ^[0-9]+$ ]] || { err "$C: no quota in the datastore, not checked"; continue; }

            if (( size > quota ))
            then
            	ntc "STOPPING $C SIZE $size IS OVER $quota"

                systemctl disable "srvctl-nspawn@$C" --no-pager
                systemctl stop "srvctl-nspawn@$C" --no-pager

            fi

        fi

    done
}
