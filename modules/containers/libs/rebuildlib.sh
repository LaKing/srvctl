#!/bin/bash

##
##   containers/libs/rebuildlib.sh — rebuild a container on a fresh rootfs
##   (sc rebuild-ve VE [phase], commands/rebuild-ve.sh).
##
##   Phases, each recorded in /srv/$C/rebuild/state once done, so a rerun
##   continues where the last one stopped and never starts over a half state:
##     snapshot  preflight; start the old container if needed, save the front
##               page through haproxy (rebuild/before.*), stop its web server
##     backup    lib/rebuild-ve-backup.sh inside it, then stop it
##     swap      fresh base image as newrootfs, then rootfs -> exrootfs and
##               newrootfs -> rootfs; ssh host keys and /srv/backup copied over
##     restore   start, lib/rebuild-ve-restore.sh inside
##     check     services, haproxy front page against the snapshot, error logs
##   rollback puts exrootfs back (the new tree is kept as rootfs.failed-*),
##   discard-old deletes exrootfs once check has passed.
##
##   Ownership: backup and restore run inside the containers, and the copies
##   between them are cp -a. The new rootfs comes from the base image owned by
##   host root, so nspawn's PrivateUsersChown shifts the whole tree at the first
##   start; uid base+N and 0+N both land on base+N. No uid arithmetic here.
##
##   The new tree is built aside and swapped with two renames: regenerate
##   (check_container_directories) recreates a missing rootfs on its own.
##

SC_REBUILD_SRV="${SC_REBUILD_SRV:-/srv}" ## test seam
SC_REBUILD_PHASES=(snapshot backup swap restore check)
SC_REBUILD_ERRORS='critical error|Error establishing a database connection|Fatal error|Parse error'
## content this rebuild cannot restore: refused unless SC_REBUILD_FORCE=true
SC_REBUILD_UNSUPPORTED='var/codepad nginx.service supervisord.service elasticsearch.service rabbitmq-server.service redis.service'

function rebuild_ssh() { ## C [command...]
    ssh -o BatchMode=yes -o ConnectTimeout=5 "$@"
}

function rebuild_is_running() { ## C
    machinectl show "$1" > /dev/null 2>&1
}

function rebuild_wait_ssh() { ## C
    local _
    for _ in {1..40}
    do
        rebuild_ssh "$1" true 2> /dev/null && return 0
        sleep 3
    done
    err "$1 does not answer ssh after start"
    return 1
}

function rebuild_stop() { ## C
    local C="$1" _
    run systemctl stop "srvctl-nspawn@$C"
    rebuild_is_running "$C" || return 0
    run machinectl poweroff "$C"
    for _ in {1..20}
    do
        rebuild_is_running "$C" || return 0
        sleep 3
    done
    run machinectl terminate "$C"
    ! rebuild_is_running "$C"
}

## front page through haproxy: <dir>/<name>.html and <name>.status (code + title).
## The query string bypasses page caches (WP Rocket, W3TC): a cached copy would
## pass the check without running any PHP (seen on r2: amajomhoz.hu).
function rebuild_fetch() { ## C name
    local C="$1" d="$SC_REBUILD_SRV/$1/rebuild" code title
    code="$(curl -sk -m 60 -o "$d/$2.html" -w '%{http_code}' --resolve "$C:443:127.0.0.1" "https://$C/?srvctl-rebuild=$(date +%s)")"
    title="$(grep -oi '<title>[^<]*' "$d/$2.html" 2> /dev/null | head -n 1 | sed 's/^<title>//I')"
    printf '%s %s\n' "$code" "$title" > "$d/$2.status"
    msg "$2: HTTP $code, title: $title"
}

function rebuild_ve_snapshot() { ## C
    local C="$1" r="$SC_REBUILD_SRV/$1/rootfs" m found=() tver
    [[ -d $r ]] || { err "$r does not exist"; return 1; }
    for m in $SC_REBUILD_UNSUPPORTED
    do
        [[ -e $r/$m || -e $r/etc/systemd/system/multi-user.target.wants/$m ]] && found+=("$m")
    done
    ## an enabled service defined here and not by a package: one whose unit
    ## lives in /srv/<dir> or /home (a Node app's /srv/app/bash/app.service) is
    ## carried by the backup with its tree; anywhere else it is an application
    ## the restore cannot bring back. Links are read, never followed (container paths).
    ## Old srvctl wrote some links with the host path of the rootfs
    ## (/srv/<C>/rootfs/usr/lib/systemd/..., seen on r2: barscale.hu): packaged too.
    for w in "$r"/etc/systemd/system/multi-user.target.wants/*
    do
        [[ -L $w ]] || continue
        case "$(readlink "$w")" in /usr/lib/systemd/* | /lib/systemd/* | ../* | /usr/share/* | /srv/*/rootfs/* | /srv/?*/* | /home/?*/*) ;; *) found+=("${w##*/} (local unit)") ;; esac
    done
    if ((${#found[@]})) && [[ ${SC_REBUILD_FORCE:-} != true ]]
    then
        err "$C has content rebuild-ve does not restore: ${found[*]} (SC_REBUILD_FORCE=true overrides)"
        return 1
    fi
    tver="$(sed -n 's/^VERSION_ID=//p' "$SC_ROOTFS_DIR/fedora/usr/lib/os-release" 2> /dev/null)"
    [[ $tver ]] || { err "no fedora base image in $SC_ROOTFS_DIR/fedora (sc regenerate rootfs)"; return 1; }
    msg "$C: $(sed -n 's/^PRETTY_NAME=//p' "$r/usr/lib/os-release" "$r/etc/os-release" 2> /dev/null | head -n 1) -> fedora $tver"

    ## first attempt only: a rerun would find the container started by us
    if [[ ! -f $SC_REBUILD_SRV/$C/rebuild/was-running ]]
    then
        rebuild_is_running "$C" && echo true > "$SC_REBUILD_SRV/$C/rebuild/was-running" || echo false > "$SC_REBUILD_SRV/$C/rebuild/was-running"
    fi
    rebuild_is_running "$C" || run systemctl start "srvctl-nspawn@$C" || return 1
    rebuild_wait_ssh "$C" || return 1
    rebuild_fetch "$C" before
    ## the old web stack is the vulnerable part: off for the rest of its life
    # shellcheck disable=SC2016 ## expands inside the container
    rebuild_ssh "$C" 'for u in httpd php-fpm nginx; do systemctl stop $u 2>/dev/null; done; true'
}

function rebuild_ve_backup() { ## C
    local C="$1"
    rebuild_is_running "$C" || { run systemctl start "srvctl-nspawn@$C" && rebuild_wait_ssh "$C"; } || return 1
    rebuild_ssh "$C" bash -s < "$SC_INSTALL_DIR/modules/containers/lib/rebuild-ve-backup.sh" || { err "backup failed in $C"; return 1; }
    rebuild_stop "$C" || { err "$C does not stop"; return 1; }
}

function rebuild_ve_swap() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    rebuild_is_running "$C" && { err "$C is running, not swapping its rootfs"; return 1; }
    ## rebuild/moved: the renames below are done, a rerun only repeats the setup
    if [[ ! -f $d/rebuild/moved ]]
    then
        [[ -d $d/exrootfs ]] && { err "$d/exrootfs exists from an earlier rebuild: roll it back or discard it"; return 1; }
        rebuild_ve_build_rootfs "$C" || return 1
    fi
    init_ve_rootfs "$C"
    create_nspawn_container_config "$C"
}

function rebuild_ve_build_rootfs() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1" k
    [[ -d $d/rootfs/srv/backup ]] || { err "no backup in $d/rootfs/srv/backup"; return 1; }

    run rm -rf "$d/newrootfs"
    mkdir -p "$d/newrootfs"
    cp -R -p "$SC_ROOTFS_DIR/fedora/." "$d/newrootfs/" || { err "base image copy failed"; return 1; }
    printf '%s' "$C" > "$d/newrootfs/etc/hostname"
    ## same host keys: users' known_hosts stay valid
    for k in "$d"/rootfs/etc/ssh/ssh_host_{rsa,ecdsa,ed25519}_key{,.pub}
    do
        [[ -f $k ]] && cp -p "$k" "$d/newrootfs/etc/ssh/" && chgrp 0 "$d/newrootfs/etc/ssh/${k##*/}"
    done
    cp -a --reflink=auto "$d/rootfs/srv/backup" "$d/newrootfs/srv/" || { err "backup copy failed"; return 1; }

    run mv "$d/rootfs" "$d/exrootfs" || return 1
    run mv "$d/newrootfs" "$d/rootfs" || { run mv "$d/exrootfs" "$d/rootfs"; return 1; }
    touch "$d/rebuild/moved"
}

function rebuild_ve_restore() { ## C
    local C="$1"
    rebuild_is_running "$C" || run systemctl start "srvctl-nspawn@$C" || return 1
    rebuild_wait_ssh "$C" || return 1
    rebuild_ssh "$C" bash -s < "$SC_INSTALL_DIR/modules/containers/lib/rebuild-ve-restore.sh" || { err "restore failed in $C"; return 1; }
}

function rebuild_ve_check() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1/rebuild" bad=0 before after u
    for u in httpd php-fpm mariadb $(sed -n 's/^localunits=//p' "$SC_REBUILD_SRV/$C/rootfs/srv/backup/manifest" 2> /dev/null)
    do
        rebuild_ssh "$C" "systemctl is-enabled -q $u 2>/dev/null && ! systemctl is-active -q $u" && { err "$u is not running in $C"; bad=1; }
    done
    rebuild_ssh "$C" 'systemctl --failed --no-legend --no-pager'
    rebuild_fetch "$C" after
    before="$(cat "$d/before.status" 2> /dev/null)"
    after="$(cat "$d/after.status")"
    ## a site that served nothing before (a bare docroot's 403, seen on r2)
    ## is not failed by the rebuild for answering the same
    if [[ ! ${after%% *} =~ ^[23] ]]
    then
        if [[ ${after%% *} == "${before%% *}" ]]
        then ntc "front page answers HTTP ${after%% *}, as it did before the rebuild"
        else err "front page answers HTTP ${after%% *} (before: ${before%% *})"; bad=1
        fi
    fi
    grep -qiE "$SC_REBUILD_ERRORS" "$d/after.html" && { err "front page shows an error: $(grep -oiE "$SC_REBUILD_ERRORS" "$d/after.html" | head -n 1)"; bad=1; }
    [[ ${before#* } == "${after#* }" ]] || ntc "title changed: before '${before#* }', after '${after#* }'"
    rebuild_ssh "$C" 'tail -n 15 /var/log/php-fpm/www-error.log /var/log/httpd/error_log 2>/dev/null'
    if ((bad == 0))
    then msg "$C check passed"
    else err "$C check FAILED: fix it and rerun 'sc rebuild-ve $C', or 'sc rebuild-ve $C rollback'"
    fi
    return $bad
}

function rebuild_ve_rollback() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    [[ -d $d/exrootfs ]] || { err "no $d/exrootfs to roll back to"; return 1; }
    rebuild_stop "$C" || return 1
    [[ -d $d/rootfs ]] && { run mv "$d/rootfs" "$d/rootfs.failed-$NOW" || return 1; }
    run mv "$d/exrootfs" "$d/rootfs" || return 1
    rm -f "$d/rebuild/state" "$d/rebuild/moved"
    [[ $(cat "$d/rebuild/was-running" 2> /dev/null) == true ]] && run systemctl start "srvctl-nspawn@$C"
    msg "$C rolled back; the rebuilt tree is kept in $d/rootfs.failed-$NOW"
}

function rebuild_ve_discard_old() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    grep -qx check "$d/rebuild/state" 2> /dev/null || { err "$C has not passed check; nothing discarded"; return 1; }
    run rm -rf "$d/exrootfs" "$d"/rootfs.failed-*
    ## closed: a later 'sc rebuild-ve' starts a new rebuild
    mv "$d/rebuild/state" "$d/rebuild/state.done-$NOW"
    rm -f "$d/rebuild/moved" "$d/rebuild/was-running"
}

function rebuild_ve() { ## C [phase]
    local C="$1" P="${2:-}" p
    mkdir -p "$SC_REBUILD_SRV/$C/rebuild"
    case "$P" in
        check | rollback) "rebuild_ve_$P" "$C" ;;
        discard-old) rebuild_ve_discard_old "$C" ;;
        '')
            for p in "${SC_REBUILD_PHASES[@]}"
            do
                grep -qx "$p" "$SC_REBUILD_SRV/$C/rebuild/state" 2> /dev/null && continue
                msg "== rebuild $C: $p"
                "rebuild_ve_$p" "$C" || { err "rebuild of $C stopped in phase $p; rerun to continue"; return 1; }
                echo "$p" >> "$SC_REBUILD_SRV/$C/rebuild/state"
            done
            ;;
        *) err "unknown phase: $P (check, rollback, discard-old)"; return 32 ;;
    esac
}
