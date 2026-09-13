#!/bin/bash
## Comount configuration lives in `get container CONTAINER comount-NAME`.
## NAME is the destination basename, unique on a host. Sources live beneath
## /var/srvctl3/comount/as-ACCOUNT followed by the full container path.
## Generated files are projections; regenerate repairs them without restarting
## unchanged containers. Like other srvctl libraries, propagate errors to the
## command/hook caller instead of changing shell options or installing traps.
[[ $SRVCTL ]] || exit 4

## Test seams, not additional host configuration.
: "${SC_COMOUNT_ROOT:=/srv}"
: "${SC_COMOUNT_STORAGE:=/var/srvctl3/comount}"
: "${SC_COMOUNT_UNIT_DIR:=/etc/systemd/system}"

function comount_valid_name {
    [[ $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9_.-]*$ && $1 != *..* ]]
}

function comount_valid_path {
    [[ $1 =~ ^/[a-zA-Z0-9_./@+-]+$ && $1 != */../* && $1 != */./* &&
       $1 != */.. && $1 != */. && $1 != *//* && $1 != */ ]]
}

function comount_local_container {
    local C="$1" host
    comount_valid_name "$C" || { err "Invalid container: $C"; return 22; }
    host="$(get container "$C" host)" || return $?
    [[ $host == "$HOSTNAME" && -d $SC_COMOUNT_ROOT/$C/rootfs ]] || {
        err "Container $C must have a rootfs on $HOSTNAME"
        return 22
    }
}

## Use srvctl's persistent UID allocation, not a running process's namespace.
## Compare the rootfs owner to it so a stale/unshifted rootfs fails explicitly.
function comount_container_ids {
    local C="$1" account="${2:-codepad}" offset uid gid
    comount_local_container "$C" || return $?
    offset="$(get container "$C" uid)" || return $?
    [[ $offset =~ ^[0-9]+$ ]] || { err "Invalid UID offset for $C"; return 22; }
    [[ $(stat -c '%u:%g' "$SC_COMOUNT_ROOT/$C/rootfs") == "$offset:$offset" ]] || {
        err "Rootfs ownership of $C differs from datastore UID $offset; restore container ownership first"
        return 22
    }
    if [[ $account == root ]]
    then
        printf '%s %s\n' "$offset" "$offset"
        return 0
    fi
    [[ $account == codepad ]] || return 22
    read -r uid gid < <(awk -F: '$1 == "codepad" { print $3, $4; exit }' "$SC_COMOUNT_ROOT/$C/rootfs/etc/passwd")
    [[ $uid =~ ^[0-9]+$ && $gid =~ ^[0-9]+$ ]] || { err "No local codepad account in $C"; return 22; }
    ((uid > 0 && gid > 0 && uid < 65536 && gid < 65536)) || { err "Codepad IDs out of range in $C"; return 22; }
    printf '%s %s\n' "$((offset + uid))" "$((offset + gid))"
}

## Set module-prefixed parameters for the current container. Both commands and
## regeneration use this one validation path. No files or datastore writes here.
function comount_parameters {
    local C="$1" source="$2" name="${3:-$(basename "${2%/}")}" allow_missing="${4:-false}" ids relative
    comount_local_container "$C" || return $?
    comount_paths "$C" "$name" || return $?
    relative="${source#"$SC_COMOUNT_STORAGE/as-"}"
    SC_COMOUNT_ACCOUNT="${relative%%/*}"
    SC_COMOUNT_DEST="/${relative#*/}"
    if [[ $source != "$SC_COMOUNT_STORAGE/as-"* ]] ||
       [[ $SC_COMOUNT_ACCOUNT != codepad && $SC_COMOUNT_ACCOUNT != root ]] ||
       ! comount_valid_path "$SC_COMOUNT_DEST" ||
       [[ ${SC_COMOUNT_DEST##*/} != "$name" ]]
    then
        err "Invalid managed comount source: $source; use add-codepad-comount-to-containers or add-root-comount-to-containers"
        return 22
    fi
    if ! comount_valid_path "$source" || [[ $(realpath -m -- "$source") != "$source" ]] ||
       [[ -e $source && ! -d $source ]] || [[ $allow_missing != true && ! -d $source ]]
    then
        err "Comount source must be a directory beneath $SC_COMOUNT_STORAGE without symlinks"
        return 22
    fi
    if [[ $SC_COMOUNT_ACCOUNT == root ]]
    then
        SC_COMOUNT_SOURCE_UID=0
        SC_COMOUNT_SOURCE_GID=0
    else
        ## Stable numeric backing IDs, matching srvctl's codepad convention.
        ## No host account is needed; target IDs come from each rootfs passwd.
        SC_COMOUNT_SOURCE_UID=804
        SC_COMOUNT_SOURCE_GID=804
    fi
    SC_COMOUNT_SOURCE="$source"
    ids="$(comount_container_ids "$C" "$SC_COMOUNT_ACCOUNT")" || return $?
    read -r SC_COMOUNT_UID SC_COMOUNT_GID <<< "$ids"
    ids="$(comount_container_ids "$C" root)" || return $?
    read -r SC_COMOUNT_ROOT_UID SC_COMOUNT_ROOT_GID <<< "$ids"
}

function comount_paths {
    local C="$1" name="$2"
    if ! comount_valid_name "$C" || ! comount_valid_name "$name"
    then
        err "Invalid container or comount identifier: $C / $name"; return 22
    fi
    SC_COMOUNT_CONTAINER="$C"
    SC_COMOUNT_NAME="$name"
    SC_COMOUNT_DEST="/srv/$name"
    SC_COMOUNT_MOUNT="$SC_COMOUNT_ROOT/$C/comount/$name"
    SC_COMOUNT_UNIT="$(systemd-escape --path --suffix=mount "$SC_COMOUNT_MOUNT")" || return $?
    SC_COMOUNT_BINDS="$SC_COMOUNT_ROOT/$C/binds/comount-$name.binds"
    SC_COMOUNT_DROPIN="$SC_COMOUNT_UNIT_DIR/srvctl-nspawn@$C.service.d/comount-$name.conf"
}

function comount_mount_config {
    local mapping="u:$SC_COMOUNT_SOURCE_UID:$SC_COMOUNT_UID:1 g:$SC_COMOUNT_SOURCE_GID:$SC_COMOUNT_GID:1"
    if [[ $SC_COMOUNT_ACCOUNT == codepad ]]
    then
        mapping+=" u:0:$SC_COMOUNT_ROOT_UID:1 g:0:$SC_COMOUNT_ROOT_GID:1"
    fi
    cat <<EOF
# srvctl comount
[Unit]
Description=srvctl comount $SC_COMOUNT_NAME
RequiresMountsFor=$SC_COMOUNT_SOURCE
PartOf=srvctl-nspawn@$SC_COMOUNT_CONTAINER.service
StopWhenUnneeded=yes

[Mount]
What=$SC_COMOUNT_SOURCE
Where=$SC_COMOUNT_MOUNT
Type=none
Options=bind,rw,X-mount.idmap=$mapping
EOF
}

function comount_bind_config {
    printf '%s\n' '# srvctl comount' '[Files]' "Bind=$SC_COMOUNT_MOUNT:$SC_COMOUNT_DEST"
}

function comount_dropin_config {
    printf '%s\n' '# srvctl comount' '[Unit]' "RequiresMountsFor=$SC_COMOUNT_MOUNT"
}

function comount_owned_file {
    [[ ! -e $1 && ! -L $1 ]] || {
        [[ -f $1 && ! -L $1 ]] && grep -qxF '# srvctl comount' "$1"
    }
}

## Enumerate named settings through the standard datastore API. No new store
## format or writer: each comount-NAME property remains a normal put/get value.
function comount_names {
    local C="$1" json names name
    json="$(out container "$C" json)" || return $?
    names="$(printf '%s' "$json" | /bin/node -e '
        const record = JSON.parse(require("fs").readFileSync(0, "utf8"));
        for (const key of Object.keys(record).sort()) {
            if (key.startsWith("comount-")) console.log(key.slice(8));
        }
    ')" || return $?
    for name in $names
    do
        comount_valid_name "$name" || { err "Invalid comount key in $C"; return 22; }
    done
    [[ -z $names ]] || printf '%s\n' "$names"
    return 0
}

## Also include generated projections so clearing a key removes only that
## named mount. The mountpoint directory finds partially generated mount units.
function comount_known_names {
    local C="$1" names name file base unit
    local -A seen=()
    names="$(comount_names "$C")" || return $?
    for name in $names; do seen[$name]=yes; done
    for file in "$SC_COMOUNT_ROOT/$C"/binds/comount-*.binds \
                "$SC_COMOUNT_UNIT_DIR/srvctl-nspawn@$C.service.d"/comount-*.conf
    do
        if [[ ! -f $file ]] || ! grep -qxF '# srvctl comount' "$file"; then continue; fi
        base="${file##*/}"; name="${base#comount-}"
        case $file in *.binds) name="${name%.binds}" ;; *.conf) name="${name%.conf}" ;; esac
        comount_valid_name "$name" || { err "Invalid generated comount name: $file"; return 22; }
        seen[$name]=yes
    done
    for file in "$SC_COMOUNT_ROOT/$C"/comount/*
    do
        [[ -d $file ]] || continue
        name="${file##*/}"
        comount_valid_name "$name" || continue
        unit="$(systemd-escape --path --suffix=mount "$file")" || return $?
        if [[ -f $SC_COMOUNT_UNIT_DIR/$unit ]] && grep -qxF '# srvctl comount' "$SC_COMOUNT_UNIT_DIR/$unit"
        then
            seen[$name]=yes
        fi
    done
    if ((${#seen[@]})); then printf '%s\n' "${!seen[@]}" | sort; fi
    return 0
}

function comount_check_identifier {
    local name="$1" source="$2" C containers host old code names other
    containers="$(get cluster container_list)" || return $?
    for C in $containers
    do
        host="$(get container "$C" host)" || return $?
        [[ $host == "$HOSTNAME" ]] || continue
        names="$(comount_names "$C")" || return $?
        for other in $names
        do
            old="$(get container "$C" "comount-$other")" || return $?
            if [[ $source == "$old/"* || $old == "$source/"* ]]
            then
                err "Comount source overlaps $old"; return 22
            fi
        done
        if old="$(get container "$C" "comount-$name")"
        then
            [[ $old == "$source" ]] || { err "Comount $name already identifies $old on $HOSTNAME"; return 22; }
        else
            code=$?; [[ $code == 100 ]] || return "$code"
        fi
    done
}

function comount_validate_files {
    local C="$1" file target entry from to _options mounts
    [[ ! -e $SC_COMOUNT_ROOT/$C/local.nspawn ]] || { err "$C/local.nspawn bypasses .binds"; return 22; }
    if mountpoint -q "$SC_COMOUNT_ROOT/$C/comount"
    then
        err "Old unnamed comount at $SC_COMOUNT_ROOT/$C/comount; remove it before adding named comounts"
        return 22
    fi
    target="$SC_COMOUNT_ROOT/$C/rootfs$SC_COMOUNT_DEST"
    for file in "$target" "$SC_COMOUNT_MOUNT"
    do
        [[ $(realpath -m -- "$file") == "$file" && ( ! -e $file || -d $file ) ]] || {
            err "Invalid or symlinked comount directory: $file"; return 22;
        }
    done
    [[ $SC_COMOUNT_SOURCE != "$SC_COMOUNT_MOUNT" && $SC_COMOUNT_SOURCE != "$SC_COMOUNT_MOUNT/"* &&
       $SC_COMOUNT_MOUNT != "$SC_COMOUNT_SOURCE/"* ]] || { err "Source overlaps comount"; return 22; }
    mounts="$(findmnt -rn -o TARGET)" || return $?
    while IFS= read -r file
    do
        [[ $file != "$SC_COMOUNT_SOURCE/"* ]] || { err "Submount in comount source: $file"; return 22; }
    done <<< "$mounts"
    if [[ -d $target && -n $(find "$target" -mindepth 1 -maxdepth 1 -print -quit) ]]
    then
        err "Comount would hide files at $target"; return 22
    fi
    for file in "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" "$SC_COMOUNT_BINDS" "$SC_COMOUNT_DROPIN"
    do
        comount_owned_file "$file" || { err "Unmanaged comount configuration: $file; remove the manual setup first"; return 22; }
    done
    if mountpoint -q "$SC_COMOUNT_MOUNT"
    then
        [[ -f $SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT ]] || { err "Unmanaged mount at $SC_COMOUNT_MOUNT"; return 22; }
    elif [[ -d $SC_COMOUNT_MOUNT && -n $(find "$SC_COMOUNT_MOUNT" -mindepth 1 -maxdepth 1 -print -quit) ]]
    then
        err "Comount directory is not empty: $SC_COMOUNT_MOUNT"; return 22
    fi
    for file in "$SC_COMOUNT_ROOT/$C"/*.binds "$SC_COMOUNT_ROOT/$C"/binds/*.binds
    do
        [[ -f $file && $file != "$SC_COMOUNT_BINDS" ]] || continue
        while IFS= read -r entry || [[ -n $entry ]]
        do
            [[ $entry =~ ^[[:space:]]*(Bind|BindReadOnly)[[:space:]]*=[[:space:]]*(.*)$ ]] || continue
            entry="${BASH_REMATCH[2]}"
            entry="${entry%"${entry##*[![:space:]]}"}"
            [[ -n $entry && $entry != *[[:space:]\"\\%]* ]] || { err "Cannot inspect bind in $file"; return 22; }
            IFS=: read -r from to _options <<< "$entry"
            to="${to:-$from}"; to="${to%/}"; from="${from%/}"
            if [[ -z $to || $to == "$SC_COMOUNT_DEST" || $to == "$SC_COMOUNT_DEST/"* ||
                  $SC_COMOUNT_DEST == "$to/"* || $from == "$SC_COMOUNT_MOUNT" ]]
            then
                err "Conflicting bind in $file: $entry"; return 22
            fi
        done < "$file"
    done
}

## Apply only changed generated configuration. Keep stopped containers stopped.
## A failure is reported through normal srvctl errors/journal; retained datastore
## intent can be retried with regenerate after correcting the cause.
function regenerate_comount {
    local C="$1" name="$2" source code file running=false mount_config bind_config dropin_config
    comount_paths "$C" "$name" || return $?
    if source="$(get container "$C" "comount-$name")"
    then
        :
    else
        code=$?
        if [[ $code == 100 ]]
        then
            ## Clearing datastore intent also removes its generated projection.
            ## Do not write the datastore from a regeneration hook (it may be RO).
            for file in "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" "$SC_COMOUNT_BINDS" "$SC_COMOUNT_DROPIN"
            do
                if [[ -f $file ]] && grep -qxF '# srvctl comount' "$file"
                then
                    remove_comount "$C" "$name" false
                    return $?
                fi
            done
            return 0
        fi
        return "$code"
    fi
    comount_parameters "$C" "$source" "$name" || return $?
    comount_validate_files "$C" || return $?
    [[ $(stat -c '%u:%g' "$SC_COMOUNT_SOURCE") == "$SC_COMOUNT_SOURCE_UID:$SC_COMOUNT_SOURCE_GID" ]] || {
        err "Source ownership differs from $SC_COMOUNT_ACCOUNT; run add-$SC_COMOUNT_ACCOUNT-comount-to-containers to assign it"; return 22;
    }
    mount_config="$(comount_mount_config)"
    bind_config="$(comount_bind_config)"
    dropin_config="$(comount_dropin_config)"
    if [[ -f $SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT && -f $SC_COMOUNT_BINDS && -f $SC_COMOUNT_DROPIN ]] &&
       [[ $(cat "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT") == "$mount_config" &&
          $(cat "$SC_COMOUNT_BINDS") == "$bind_config" && $(cat "$SC_COMOUNT_DROPIN") == "$dropin_config" ]]
    then
        debug "Comount configuration unchanged for $C"
        return 0
    fi
    msg "Regenerate comount for $C: $SC_COMOUNT_SOURCE -> $SC_COMOUNT_DEST"
    if systemctl is-active --quiet "srvctl-nspawn@$C.service"
    then
        running=true
        run systemctl stop "srvctl-nspawn@$C.service" || return $?
    fi
    if mountpoint -q "$SC_COMOUNT_MOUNT"
    then
        run systemctl stop "$SC_COMOUNT_UNIT" || return $?
    fi
    mkdir -p "$SC_COMOUNT_MOUNT" "${SC_COMOUNT_BINDS%/*}" "${SC_COMOUNT_DROPIN%/*}" "$SC_COMOUNT_UNIT_DIR" "$SC_COMOUNT_ROOT/$C/rootfs$SC_COMOUNT_DEST" || return $?
    printf '%s\n' "$mount_config" > "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" || return $?
    printf '%s\n' "$bind_config" > "$SC_COMOUNT_BINDS" || return $?
    printf '%s\n' "$dropin_config" > "$SC_COMOUNT_DROPIN" || return $?
    chmod 644 "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" "$SC_COMOUNT_BINDS" "$SC_COMOUNT_DROPIN" || return $?
    run systemctl daemon-reload || return $?
    if $running
    then
        run systemctl start "srvctl-nspawn@$C.service" || return $?
    fi
    return 0
}

function add_comount_to_containers {
    local account="${1:-}" destination="${2:-}" source name C
    local -a targets=()
    local -A seen=()
    (($# >= 3)) || { err "Usage: add-{codepad,root}-comount-to-containers PATH CONTAINER..."; return 32; }
    shift 2
    [[ $account == codepad || $account == root ]] || { err "Invalid comount account: $account"; return 22; }
    destination="${destination%/}"
    comount_valid_path "$destination" || { err "Invalid absolute container path: $destination"; return 22; }
    name="${destination##*/}"
    comount_valid_name "$name" || { err "Invalid comount identifier: $name"; return 22; }
    source="$SC_COMOUNT_STORAGE/as-$account$destination"
    comount_check_identifier "$name" "$source" || return $?
    ## Validate every target before creating storage or changing ownership.
    for C in "$@"
    do
        comount_valid_name "$C" || { err "Invalid container: $C"; return 22; }
        [[ ! ${seen[$C]+yes} ]] || continue
        seen[$C]=yes
        comount_parameters "$C" "$source" "$name" true || return $?
        comount_validate_files "$C" || return $?
        targets+=("$C")
    done
    msg "Assign $source and its files to $account ($SC_COMOUNT_SOURCE_UID:$SC_COMOUNT_SOURCE_GID)"
    run mkdir -p "$source" || return $?
    run chown -hR "$SC_COMOUNT_SOURCE_UID:$SC_COMOUNT_SOURCE_GID" "$source" || return $?
    find "$source" -xdev -type d -exec chmod u+rwx {} + || return $?
    find "$source" -xdev -type f -exec chmod u+rw {} + || return $?
    for C in "${targets[@]}"
    do
        put container "$C" "comount-$name" "$source" || return $?
        regenerate_comount "$C" "$name" || return $?
    done
}

function remove_comount {
    ## Third argument is false only for cleanup from the regenerate hook.
    local C="$1" name="$2" delete_setting="${3:-true}" file running=false
    comount_local_container "$C" || return $?
    comount_paths "$C" "$name" || return $?
    for file in "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" "$SC_COMOUNT_BINDS" "$SC_COMOUNT_DROPIN"
    do
        comount_owned_file "$file" || { err "Not module-owned: $file"; return 22; }
    done
    if mountpoint -q "$SC_COMOUNT_MOUNT" && [[ ! -f $SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT ]]
    then
        err "Unmanaged mount for $C"; return 22
    fi
    msg "Remove comount $name from $C; keep source files"
    if systemctl is-active --quiet "srvctl-nspawn@$C.service"
    then
        running=true
        run systemctl stop "srvctl-nspawn@$C.service" || return $?
    fi
    if mountpoint -q "$SC_COMOUNT_MOUNT"
    then
        run systemctl stop "$SC_COMOUNT_UNIT" || return $?
    fi
    if [[ $delete_setting == true ]]
    then
        put container "$C" "comount-$name" || return $?
    fi
    run rm -f "$SC_COMOUNT_UNIT_DIR/$SC_COMOUNT_UNIT" "$SC_COMOUNT_BINDS" "$SC_COMOUNT_DROPIN" || return $?
    run systemctl daemon-reload || return $?
    if $running
    then
        run systemctl start "srvctl-nspawn@$C.service" || return $?
    fi
    return 0
}

function regenerate_comounts {
    local C containers host names name
    containers="$(get cluster container_list)" || return $?
    for C in $containers
    do
        host="$(get container "$C" host)" || return $?
        [[ $host == "$HOSTNAME" ]] || continue
        names="$(comount_known_names "$C")" || return $?
        for name in $names
        do
            regenerate_comount "$C" "$name" || return $?
        done
    done
}

function test_comount {
    local C="$1" name="$2" source account
    local -a accounts=(root)
    comount_paths "$C" "$name" || return $?
    source="$(get container "$C" "comount-$name")" || return $?
    comount_parameters "$C" "$source" "$name" || return $?
    [[ $SC_COMOUNT_ACCOUNT != codepad ]] || accounts=(codepad root)
    for account in "${accounts[@]}"
    do
        msg "Test comount $name in $C as $account"
        ## Root service + runuser avoids the observed --uid/--pipe EXIT_STDIN=208.
        ## Invoke directly: run word-splits arguments, including the shell program.
        # shellcheck disable=SC2016
        systemd-run -M "$C" --wait --pipe --collect /usr/sbin/runuser -u "$account" -- /bin/sh -ec '
            cd "$1"
            id
            stat -c "%U:%G %A %n" .
            d=$(mktemp -d .comount-check.XXXXXX)
            trap '\''rm -f "$d/file"; rmdir "$d"'\'' EXIT
            echo "write works" > "$d/file"
            echo "append works" >> "$d/file"
            cat "$d/file"
            stat -c "%U:%G %n" "$d" "$d/file"
        ' sh "$SC_COMOUNT_DEST" </dev/null || return $?
    done
}

function diagnose_comounts {
    local C containers host source names name
    containers="$(get cluster container_list)" || return $?
    for C in $containers
    do
        host="$(get container "$C" host)" || return $?
        [[ $host == "$HOSTNAME" ]] || continue
        names="$(comount_names "$C")" || return $?
        for name in $names
        do
            source="$(get container "$C" "comount-$name")" || return $?
            comount_paths "$C" "$name" || return $?
            msg "Comount $name in $C: $source"
            run systemctl status "$SC_COMOUNT_UNIT" --no-pager -n 10 || true
            run findmnt -T "$SC_COMOUNT_MOUNT" || true
        done
    done
}
