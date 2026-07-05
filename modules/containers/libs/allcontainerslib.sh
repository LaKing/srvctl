#!/bin/bash

##
##   containers/libs/allcontainerslib.sh — iterate a command over every
##   container of the cluster.
##
##   all_containers_execute backs 'sc exec-all'; all_containers_pingback
##   backs the diagnose hook. Both walk the cluster container list (root)
##   or the caller's own list, treating containers without a local /srv
##   dir as remote (ssh to their recorded host).
##

function all_containers_execute() { ## cmd
    local list host cmd temp_file
    cmd="$1"

    msg "Command is: $cmd"

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
            msg "$HOSTNAME / $C"
            
            if systemctl is-active srvctl-nspawn@"$C" >/dev/null 2>&1
            then
                ## this is a solution .. direct call causes some shell weirdness
                ## (run/direct invocation re-splits $cmd; the temp file
                ## preserves the quoting — nur only prints the command line)
                nur machinectl -q --no-pager shell "$C" "/bin/bash/ -c '$cmd'"
                temp_file=$(mktemp)
                echo "machinectl -q --no-pager shell $C /bin/bash/ -c '$cmd'" > "$temp_file"
                /bin/bash "$temp_file"
                rm -fr "$temp_file"
            else
                err "Container $C is inactive"
            fi
        else
            host="$(get container "$C" host)"
            msg "$host / $C"
            
            if ssh "$host" systemctl is-active srvctl-nspawn@"$C" >/dev/null 2>&1
            then
                run "ssh $host srvctl $C $cmd"
            else
                err "Container $C is inactive on $host"
            fi
            
        fi
        
    done
}

function all_containers_pingback() {
    local list host cmd temp_file dom ip
    cmd="$1"
    ## FIXME(v4): hard-coded reference targets — the message even claims
    ## $SC_DNS1 while the actual ping goes to 8.8.8.8 and d250.hu.
    dom="d250.hu"
    ip="8.8.8.8"
    msg "Checking all container's pingback to $SC_DNS1 and $dom"

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
            
            if systemctl is-active srvctl-nspawn@"$C" >/dev/null 2>&1
            then
                if timeout 1 ssh "$C" "ping -c 1 -W 1 $ip >/dev/null 2>&1"  2>/dev/null #2>&1
                then
                    msg "$C ping $ip OK"
                else
                    err "$C NO - ping $ip failed."
                fi
                if timeout 1 ssh "$C" "ping -c 1 -W 1 $dom >/dev/null 2>&1"  2>/dev/null #2>&1
                then
                    msg "$C ping $dom OK"
                else
                    err "$C NO - ping $dom failed."
                fi
            else
                err "Container $C is inactive"
            fi
        fi
    done
}
