#!/bin/bash

##
##   usersonhost/libs/prunelib.sh — take back the shares nobody is entitled to.
##
##   main.js gives every user of a container (owner, users, readers) the
##   directory HOME/C with the container's rootfs bindfs-mounted at
##   HOME/C/bindfs and its docroot at HOME/C/html. Nothing took a share back:
##   after remove-ve, or after a user was taken off a container, the mount
##   stayed and kept serving the tree until the next boot.
##
##   A share is recognised without trusting the user, who owns HOME: HOME/C is
##   a real directory owned by root (main.js creates it as root) that holds
##   nothing but the two mount points. Its mounts are unmounted lazily (a shell
##   sitting in the tree must not block it) and the empty directories removed
##   with rmdir; nothing is ever deleted recursively in a home.
##   A domain-only record (retire-ve) entitles nobody to a share: its rootfs is gone.
##

function prune_user_shares {
    local rows C owner users readers u home share names mp
    local -A wanted

    [[ -n ${SC_PRUNE_CONTAINERS:-} ]] || return 0

    ## users and readers are JSON lists of names, '-' when unset
    rows="$(list container user users readers)" || return 0
    while IFS=$'\t' read -r C owner users readers
    do
        container_is_retired "$C" && continue
        for u in $owner ${users//[\[\]\",]/ } ${readers//[\[\]\",]/ }
        do
            wanted[$u/$C]=yes
        done
    done <<< "$rows"

    rows="$(list user)" || return 0
    for u in $rows
    do
        [[ $u != root ]] || continue
        home="$(getent passwd "$u" | cut -d: -f6)"
        [[ $home == /*/* && -d $home && ! -L $home ]] || continue

        for share in "$home"/*
        do
            C="${share##*/}"
            [[ -z ${wanted[$u/$C]:-} ]] || continue
            [[ -d $share && ! -L $share && $(stat -c %u "$share") == 0 ]] || continue
            ## ls, not a test on the entries: a dead bindfs mount fails every stat
            names="$(ls -A "$share" 2> /dev/null)"
            [[ -z $names || $names == bindfs || $names == $'bindfs\nhtml' ]] || continue

            if [[ ${SC_PRUNE_DRY_RUN:-false} == true ]]
            then
                ntc "Leftover (dry run, not removed): $share"
                continue
            fi
            ntc "Removing leftover share $share"
            logs "prune share $share"
            ## deepest first, the literal paths of the mount table only
            while read -r -u 3 mp
            do
                umount -l "$mp"
            done 3< <(mounts_in "$share")
            rmdir "$share/html" "$share/bindfs" 2> /dev/null
            rmdir "$share" || err "Could not remove the share directory $share"
        done
    done
}
