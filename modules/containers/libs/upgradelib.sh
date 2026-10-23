#!/bin/bash

##
##   containers/libs/upgradelib.sh — upgrade a container's Fedora in place
##   (sc upgrade-ve VE [phase], commands/upgrade-ve.sh). The alternative to
##   rebuild-ve for containers whose content a rebuild cannot carry: the whole
##   tree stays, only its packages move to the release of the fedora base image.
##
##   Phases, recorded in /srv/$C/upgrade/state like rebuildlib's:
##     prepare  release gap (at most 2, as dnf system-upgrade supports), disk
##              space, front page (upgrade/before.*), running services and
##              enabled unit links of the old tree
##     copy     stop the container, cp -a rootfs to exrootfs (the rollback)
##     upgrade  third-party repo URLs to the new release, dnf distro-sync in a
##              throwaway nspawn of the stopped tree, lost enabled links back
##     check    start, release, services, front page against the one before
##   rollback and discard-old as in rebuildlib; both share exrootfs, so each
##   refuses while the other one's run is open.
##
##   Why not dnf inside the running container: srvctl binds /etc/systemd/network
##   read-only from the host, and rpm cannot unpack the systemd package over it
##   ("cpio: chown failed"). The transaction stops half done, systemd from the
##   old release over the new release's libraries (seen on r2: comedia.kassa.hu,
##   bp: stream.m1r0.de). The throwaway nspawn has no srvctl binds; it maps the
##   tree's own uid base, so file owners stay as the running container sees them.
##
##   An upgrade also drops wants links (postfix on comedia.kassa.hu); a service
##   started by hand and never enabled (caddy there) does not come back after the
##   stop. The check names both.
##

SC_UPGRADE_PHASES=(prepare copy upgrade check)

function upgrade_release_of() { ## rootfs
    sed -n 's/^VERSION_ID=//p' "$1/usr/lib/os-release" "$1/etc/os-release" 2> /dev/null | head -n 1
}

function upgrade_ve_prepare() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1" u="$SC_REBUILD_SRV/$1/upgrade" from to size avail
    [[ -d $d/rootfs ]] || { err "$d/rootfs does not exist"; return 1; }
    [[ -d $d/exrootfs ]] && { err "$d/exrootfs exists from an earlier rebuild or upgrade: roll it back or discard it"; return 1; }
    [[ -f $d/rebuild/state ]] && { err "a rebuild-ve of $C is open: finish it with rollback or discard-old first"; return 1; }
    grep -qE '^ID="?fedora' "$d/rootfs/usr/lib/os-release" "$d/rootfs/etc/os-release" 2> /dev/null || { err "$C is not a Fedora container"; return 1; }
    from="$(upgrade_release_of "$d/rootfs")"
    to="$(upgrade_release_of "$SC_ROOTFS_DIR/fedora")"
    [[ $to ]] || { err "no fedora base image in $SC_ROOTFS_DIR/fedora (sc regenerate rootfs)"; return 1; }
    ((from <= to)) || { err "$C is on fedora $from, newer than the base image's $to"; return 1; }
    ## the same release is allowed: a distro-sync repairs a half done transaction
    if ((to - from > 2)) && [[ ${SC_UPGRADE_FORCE:-} != true ]]
    then
        err "$C is on fedora $from: more than 2 releases behind $to, use rebuild-ve (SC_UPGRADE_FORCE=true overrides)"
        return 1
    fi
    ## the copy plus the downloaded packages
    size="$(du -sxB1 "$d/rootfs" | cut -f1)"
    avail="$(df --output=avail -B1 "$d" | tail -n 1)"
    ((avail > size + 2 * 1024 ** 3)) || { err "$C needs $((size / 1024 ** 3))G + 2G free for the copy, $d has $((avail / 1024 ** 3))G"; return 1; }
    msg "$C: fedora $from -> $to, copy of $((size / 1024 ** 3))G"
    echo "$from $to" > "$u/release"

    (cd "$d/rootfs/etc/systemd/system" && find . -path '*.wants/*' -type l | sort) > "$u/enabled-before"
    : > "$u/running-before"
    rm -f "$u/before.status"
    if rebuild_is_running "$C"
    then
        echo true > "$u/was-running"
        rebuild_wait_ssh "$C" || return 1
        ## login sessions (this ssh among them) are not services to expect back
        rebuild_ssh "$C" 'systemctl list-units --type=service --state=running --no-legend --plain' | awk '$1 !~ /^user(-runtime-dir)?@/ {print $1}' > "$u/running-before"
        rebuild_fetch "$C" before "$u"
    else
        echo false > "$u/was-running"
    fi
}

function upgrade_ve_copy() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    rebuild_stop "$C" || { err "$C does not stop"; return 1; }
    ## copied aside first: a rerun after an interrupted copy never takes a partial tree for the rollback
    run rm -rf "$d/exrootfs.partial"
    run cp -a --reflink=auto "$d/rootfs" "$d/exrootfs.partial" || { err "copy failed"; return 1; }
    run mv "$d/exrootfs.partial" "$d/exrootfs"
}

function upgrade_ve_upgrade() { ## C
    local C="$1" r="$SC_REBUILD_SRV/$1/rootfs" u="$SC_REBUILD_SRV/$1/upgrade" from to f base opts
    read -r from to < "$u/release"
    rebuild_is_running "$C" && { rebuild_stop "$C" || return 1; }

    ## a repo with the release in its URL (zerotier's .../fc/43) keeps serving the
    ## old builds; $releasever ones follow by themselves. Fedora's own are left to dnf.
    ## Rewritten with cat: the file keeps its owner, which is the shifted uid.
    for f in "$r"/etc/yum.repos.d/*.repo
    do
        [[ -f $f && $from != "$to" ]] || continue
        grep -q fedoraproject.org "$f" && continue
        grep -qE "^(baseurl|metalink|mirrorlist)=.*[^0-9]$from([^0-9]|$)" "$f" || continue
        sed -E "/^(baseurl|metalink|mirrorlist)=/s/([^0-9])$from([^0-9]|$)/\\1$to\\2/g" "$f" > "$u/repo.tmp" && cat "$u/repo.tmp" > "$f"
        msg "${f#"$r"}: release $from -> $to in its URLs"
    done
    rm -f "$u/repo.tmp"

    base="$(stat -c %u "$r")"
    ## no systemd runs in it: a scriptlet's bare 'systemctl stop' would fail and abort the package
    ## (dovecot's %pre, seen on r2: tancaszabadsagert.hu); offline, systemctl skips it with 0
    opts=(-q -D "$r" -M "upgrade-$C" --resolv-conf=replace-host --setenv=SYSTEMD_OFFLINE=1)
    ((base)) && opts+=("--private-users=$base:65536")
    touch "$u/started"
    ## the new release's signing key first; a third-party repo without a build for it is skipped, not fatal.
    ## Not through lablib's run: it executes an unquoted $*, which splits the bash -c script into words.
    msg "systemd-nspawn ${opts[*]}: dnf distro-sync --releasever=$to"
    systemd-nspawn "${opts[@]}" bash -c "dnf -y upgrade --refresh fedora-gpg-keys; dnf -y --releasever=$to --setopt=skip_if_unavailable=True distro-sync --allowerasing && echo \"== packages still built for fedora $from: \$(rpm -qa --qf '%{RELEASE}\n' | grep -c 'fc$from\$')\"" || {
        err "dnf distro-sync failed in $r; rerun to retry, or rollback"
        return 1
    }
    upgrade_restore_links "$C"
    ## -cnewer: rpm gives a file the mtime it has in the package, only the ctime is of now
    find "$r/etc" -name '*.rpmnew' -cnewer "$u/started" 2> /dev/null | while read -r f
    do
        ntc "new default config kept aside: ${f#"$r"} (the old ${f#"$r"} stays in use)"
    done
}

## enabled links the upgrade removed, put back from the copy when their unit still exists
function upgrade_restore_links() { ## C
    local C="$1" s="etc/systemd/system" d="$SC_REBUILD_SRV/$1" l t
    while read -r l
    do
        [[ -L $d/rootfs/$s/$l ]] && continue
        t="$(readlink "$d/exrootfs/$s/$l")"
        [[ $t == /* ]] && t="$d/rootfs$t" || t="$d/rootfs/$s/$(dirname "$l")/$t"
        if [[ -e $t ]]
        then
            (cd "$d/exrootfs/$s" && cp -a --parents "$l" "$d/rootfs/$s/") && msg "enabled again: ${l#./}"
        else
            ntc "${l#./} was enabled, its unit is gone after the upgrade"
        fi
    done < "$SC_REBUILD_SRV/$C/upgrade/enabled-before"
}

function upgrade_ve_check() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1" u="$SC_REBUILD_SRV/$1/upgrade" bad=0 from to rel s
    read -r from to < "$u/release"
    rebuild_is_running "$C" || run systemctl start "srvctl-nspawn@$C" || return 1
    rebuild_wait_ssh "$C" || return 1
    rebuild_ssh "$C" 'timeout 120 systemctl is-system-running --wait > /dev/null'
    rel="$(upgrade_release_of "$d/rootfs")"
    [[ $rel == "$to" ]] || { err "$C reports fedora $rel, not $to"; bad=1; }
    ## what ran before; when it was stopped, what was enabled for boot
    {
        cat "$u/running-before"
        [[ -s $u/running-before ]] || sed -n 's|^\./multi-user.target.wants/\(.*\.service\)$|\1|p' "$u/enabled-before"
    } | sort -u > "$u/expected-services"
    while read -r s
    do
        rebuild_ssh "$C" "systemctl is-active -q '$s'" && continue
        if rebuild_ssh "$C" "systemctl is-enabled -q '$s' 2>/dev/null"
        then err "$s is not running in $C"
        else err "$s ran before the upgrade, is not running now and is not enabled (started by hand?)"
        fi
        bad=1
    done < "$u/expected-services"
    rebuild_ssh "$C" 'systemctl --failed --no-legend --no-pager'
    if [[ -f $u/before.status ]]
    then rebuild_compare_front_page "$C" "$u" || bad=1
    else rebuild_fetch "$C" after "$u"; ntc "no front page from before the upgrade to compare with (the container was stopped)"
    fi
    if ((bad == 0))
    then msg "$C check passed: fedora $to"
    else err "$C check FAILED: fix it and rerun 'sc upgrade-ve $C check', or 'sc upgrade-ve $C rollback'"
    fi
    return $bad
}

function upgrade_ve_rollback() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    if ! grep -qx copy "$d/upgrade/state" 2> /dev/null || [[ ! -d $d/exrootfs ]]
    then
        err "no upgrade copy of $C to roll back to"
        return 1
    fi
    rebuild_stop "$C" || return 1
    run mv "$d/rootfs" "$d/rootfs.failed-$NOW" || return 1
    run mv "$d/exrootfs" "$d/rootfs" || return 1
    mv "$d/upgrade/state" "$d/upgrade/state.rolled-back-$NOW"
    [[ $(cat "$d/upgrade/was-running" 2> /dev/null) == true ]] && run systemctl start "srvctl-nspawn@$C"
    msg "$C rolled back; the upgraded tree is kept in $d/rootfs.failed-$NOW"
}

function upgrade_ve_discard_old() { ## C
    local C="$1" d="$SC_REBUILD_SRV/$1"
    grep -qx check "$d/upgrade/state" 2> /dev/null || { err "$C has not passed the upgrade check; nothing discarded"; return 1; }
    run rm -rf "$d/exrootfs" "$d"/rootfs.failed-*
    mv "$d/upgrade/state" "$d/upgrade/state.done-$NOW"
}

function upgrade_ve() { ## C [phase]
    local C="$1" P="${2:-}" p
    mkdir -p "$SC_REBUILD_SRV/$C/upgrade"
    case "$P" in
        check | rollback) "upgrade_ve_$P" "$C" ;;
        discard-old) upgrade_ve_discard_old "$C" ;;
        '')
            for p in "${SC_UPGRADE_PHASES[@]}"
            do
                grep -qx "$p" "$SC_REBUILD_SRV/$C/upgrade/state" 2> /dev/null && continue
                msg "== upgrade $C: $p"
                "upgrade_ve_$p" "$C" || { err "upgrade of $C stopped in phase $p; rerun to continue"; return 1; }
                echo "$p" >> "$SC_REBUILD_SRV/$C/upgrade/state"
            done
            ;;
        *) err "unknown phase: $P (check, rollback, discard-old)"; return 32 ;;
    esac
}
