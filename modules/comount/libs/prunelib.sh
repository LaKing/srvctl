#!/bin/bash

##
##   comount/libs/prunelib.sh — remove the mount units of removed containers.
##
##   A comount is a mount unit in the system unit directory, named after its
##   mount point /srv/C/comount/NAME (comountlib.sh, comount_paths). remove-ve
##   and destroy-ve unmount and delete /srv/C, the container's bind file and
##   its drop-in directory go with the container, and the unit file is what
##   stays behind. Only files carrying the module's own marker line are touched.
##

function prune_comount_units {
    local file where C reload=false

    for file in "$SC_COMOUNT_UNIT_DIR"/*-comount-*.mount
    do
        [[ -f $file ]] || continue
        grep -qxF '# srvctl comount' "$file" || continue
        where="$(sed -n 's/^Where=//p' "$file")"
        [[ $where == "$SC_COMOUNT_ROOT"/*/comount/* ]] || continue
        C="${where#"$SC_COMOUNT_ROOT"/}"
        C="${C%%/*}"
        container_is_gone "$C" || continue
        prune "$file"
        reload=true
    done

    [[ ${SC_PRUNE_DRY_RUN:-false} != true ]] || return 0
    $reload && systemctl daemon-reload
}
