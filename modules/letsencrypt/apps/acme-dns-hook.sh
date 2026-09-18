#!/bin/bash

##
##   modules/letsencrypt/apps/acme-dns-hook.sh — certbot DNS-01 hooks.
##
##   certbot --manual --manual-auth-hook "<this> auth"
##                    --manual-cleanup-hook "<this> cleanup"
##   letsencrypt.js    "<this> reconcile"   (on the DNS primary, every run)
##
##   Runs standalone (certbot starts it, also for renewals outside srvctl):
##   it reads nothing from srvctl but its own configuration file
##   ${SC_ACME_HOOK_CONF:-/etc/letsencrypt/srvctl-acme-dns.conf}, written by
##   letsencrypt.js on the primary, KEY=VALUE lines:
##     ACME_ZONE        _acme.<company-domain>
##     ACME_KEY         TSIG key file (tsig-keygen, hmac-sha256)
##     ACME_PRIMARY     primary address (nsupdate target)
##     ACME_SECONDARIES space separated secondary addresses
##     ACME_TTL ACME_TIMEOUT ACME_POLL   TXT ttl, visibility timeout, poll s
##     ACME_STATE_DIR   in-flight records;  ACME_LOCK  records lock file
##
##   auth     checks the live _acme-challenge.<domain> CNAME on the primary
##            points into ACME_ZONE, records the challenge with its owning
##            certbot process (pid, start time, boot id), adds the TXT with
##            nsupdate and returns only when the primary and every secondary
##            serve the whole chain the CA follows: the CNAME to the target
##            and the TXT value at the target. Non-zero on timeout.
##   cleanup  deletes exactly that TXT value; a failed delete is marked
##            cleanupFailed (stderr, certbot log) and the hook exits 0.
##   reconcile retries/removes a failed or left-over record only when its
##            owner has provably ended (/proc/<pid> gone, or a different
##            start time or boot id). Live and unknown owners are reported.
##
##   SC_ACME_PROC overrides /proc for the selftest.
##

set -u

CONF="${SC_ACME_HOOK_CONF:-/etc/letsencrypt/srvctl-acme-dns.conf}"
PROC="${SC_ACME_PROC:-/proc}"

ACME_ZONE="" ACME_KEY="" ACME_PRIMARY="" ACME_SECONDARIES="" ACME_TTL=60
ACME_TIMEOUT=180 ACME_POLL=2 ACME_STATE_DIR="/var/srvctl3/acme/hook" ACME_LOCK="/run/srvctl-acme-records.lock"

function fail {
    echo "acme-dns-hook: $*" >&2
    exit 1
}

## read_conf: KEY=VALUE lines, known keys only, never sourced
function read_conf {
    local key value
    [[ -r "$CONF" ]] || fail "cannot read $CONF"
    while IFS='=' read -r key value
    do
        case "$key" in
            ACME_ZONE|ACME_KEY|ACME_PRIMARY|ACME_SECONDARIES|ACME_TTL|ACME_TIMEOUT|ACME_POLL|ACME_STATE_DIR|ACME_LOCK)
                printf -v "$key" '%s' "$value" ;;
        esac
    done < "$CONF"
    [[ "$ACME_ZONE" =~ ^_acme\.[a-z0-9.-]+$ ]] || fail "invalid ACME_ZONE in $CONF"
    [[ -n "$ACME_PRIMARY" && -n "$ACME_KEY" ]] || fail "ACME_PRIMARY/ACME_KEY missing in $CONF"
    [[ "$ACME_TTL$ACME_TIMEOUT$ACME_POLL" =~ ^[0-9]+$ ]] || fail "invalid timing values in $CONF"
    mkdir -p "$ACME_STATE_DIR/inflight"
}

function lock_records {
    exec {LOCK_FD}>> "$ACME_LOCK"
    flock -w 60 "$LOCK_FD" || fail "records lock $ACME_LOCK not obtained"
}

function unlock_records {
    flock -u "$LOCK_FD"
    exec {LOCK_FD}>&-
}

## proc_starttime PID: field 22 of /proc/PID/stat (after the comm field)
function proc_starttime {
    local stat rest
    stat="$(cat "$PROC/$1/stat" 2> /dev/null)" && [[ -n "$stat" ]] || return 1
    rest="${stat##*) }"
    read -r -a fields <<< "$rest"
    ## rest starts at field 3 (state), so field 22 is index 19
    echo "${fields[19]:-}"
}

function boot_id {
    cat "$PROC/sys/kernel/random/boot_id" 2> /dev/null || echo unknown
}

## certbot_owner: "<pid> <starttime>" of the nearest certbot/letsencrypt
## ancestor of this hook, or nothing (owner unknown)
function certbot_owner {
    local pid="$PPID" hops=0 cmd stat rest
    while [[ "$pid" =~ ^[0-9]+$ ]] && (( pid > 1 && hops < 32 ))
    do
        cmd="$(tr '\0' ' ' < "$PROC/$pid/cmdline" 2> /dev/null)"
        if [[ " $cmd" =~ [[:space:]/](certbot|letsencrypt)([[:space:]]|$) ]]
        then
            echo "$pid $(proc_starttime "$pid")"
            return 0
        fi
        stat="$(cat "$PROC/$pid/stat" 2> /dev/null)" && [[ -n "$stat" ]] || return 1
        rest="${stat##*) }"
        read -r -a fields <<< "$rest"
        pid="${fields[1]:-}"
        hops=$((hops + 1))
    done
    return 1
}

function record_file {
    local id
    id="$(printf '%s|%s' "$1" "$2" | sha256sum)"
    echo "$ACME_STATE_DIR/inflight/${id%% *}.rec"
}

## write_record FILE target value pid starttime bootid status
function write_record {
    local file="$1" tmp
    tmp="$file.tmp.$$"
    printf 'target=%s\nvalue=%s\npid=%s\nstarttime=%s\nbootid=%s\nstatus=%s\n' \
        "$2" "$3" "$4" "$5" "$6" "$7" > "$tmp" && mv -f "$tmp" "$file"
}

## read_record FILE: sets r_target r_value r_pid r_starttime r_bootid r_status
function read_record {
    local key value
    r_target="" r_value="" r_pid="" r_starttime="" r_bootid="" r_status=""
    while IFS='=' read -r key value
    do
        case "$key" in
            target|value|pid|starttime|bootid|status) printf -v "r_$key" '%s' "$value" ;;
        esac
    done < "$1"
}

function cname_of {
    local answer
    answer="$(dig +time=2 +tries=1 +norecurse +short "@$1" "$2" CNAME 2> /dev/null)"
    echo "${answer%%$'\n'*}"
}

function nsupdate_txt { ## add|delete target value
    local op="$1" ttl=""
    [[ "$op" == add ]] && ttl=" $ACME_TTL"
    printf 'server %s\nzone %s\nupdate %s %s%s IN TXT "%s"\nsend\n' \
        "$ACME_PRIMARY" "$ACME_ZONE" "$op" "$2" "$ttl" "$3" | nsupdate -k "$ACME_KEY"
}

## chain_visible SERVER DOMAIN TARGET VALUE: CNAME and TXT both served
function chain_visible {
    local cname txt
    cname="$(cname_of "$1" "_acme-challenge.$2")"
    [[ "$cname" == "$3." ]] || return 1
    txt="$(dig +time=2 +tries=1 +norecurse +short "@$1" "$3" TXT 2> /dev/null)"
    [[ $'\n'"$txt"$'\n' == *$'\n'"\"$4\""$'\n'* ]]
}

function validated_input {
    DOMAIN="${CERTBOT_DOMAIN:-}"
    DOMAIN="${DOMAIN,,}"
    DOMAIN="${DOMAIN%.}"
    VALUE="${CERTBOT_VALIDATION:-}"
    [[ "$DOMAIN" =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || fail "invalid CERTBOT_DOMAIN"
    [[ "$VALUE" =~ ^[A-Za-z0-9_-]{16,128}$ ]] || fail "invalid CERTBOT_VALIDATION"
}

function do_auth {
    local target owner pid="" start="" file server deadline
    validated_input
    target="$(cname_of "$ACME_PRIMARY" "_acme-challenge.$DOMAIN")"
    target="${target%.}"
    [[ "$target" == *".$ACME_ZONE" ]] || fail "_acme-challenge.$DOMAIN does not point into $ACME_ZONE (got '${target:-nothing}'); not publishing"

    if owner="$(certbot_owner)"
    then
        read -r pid start <<< "$owner"
    fi
    file="$(record_file "$target" "$VALUE")"
    lock_records
    write_record "$file" "$target" "$VALUE" "${pid:-unknown}" "${start:-unknown}" "$(boot_id)" inflight
    unlock_records

    if ! nsupdate_txt add "$target" "$VALUE"
    then
        lock_records; rm -f "$file"; unlock_records
        fail "nsupdate add failed for $target"
    fi

    deadline=$((SECONDS + ACME_TIMEOUT))
    while :
    do
        local all=true
        for server in $ACME_PRIMARY $ACME_SECONDARIES
        do
            chain_visible "$server" "$DOMAIN" "$target" "$VALUE" || { all=false; break; }
        done
        $all && return 0
        (( SECONDS >= deadline )) && fail "challenge chain for $DOMAIN not visible on $server within ${ACME_TIMEOUT}s"
        sleep "$ACME_POLL"
    done
}

function do_cleanup {
    local file target
    validated_input
    file="$(record_file_for_value)"
    if [[ -n "$file" ]]
    then
        read_record "$file"
        target="$r_target"
    else
        target="$(cname_of "$ACME_PRIMARY" "_acme-challenge.$DOMAIN")"
        target="${target%.}"
        [[ "$target" == *".$ACME_ZONE" ]] || { echo "acme-dns-hook: cleanup: no target for $DOMAIN" >&2; exit 0; }
        file="$(record_file "$target" "$VALUE")"
    fi
    lock_records
    if nsupdate_txt delete "$target" "$VALUE"
    then
        rm -f "$file"
    else
        echo "acme-dns-hook: cleanup of $target TXT failed; left for reconcile" >&2
        if [[ -f "$file" ]]
        then
            read_record "$file"
            write_record "$file" "$r_target" "$r_value" "$r_pid" "$r_starttime" "$r_bootid" cleanupFailed
        fi
    fi
    unlock_records
    exit 0
}

## the record of this challenge, found by value (the target comes from it)
function record_file_for_value {
    local f
    for f in "$ACME_STATE_DIR"/inflight/*.rec
    do
        [[ -f "$f" ]] || continue
        read_record "$f"
        if [[ "$r_value" == "$VALUE" ]] && [[ "$r_target" == *".$ACME_ZONE" ]]
        then
            echo "$f"
            return
        fi
    done
}

## owner_ended: 0 when the recorded owner provably no longer runs
function owner_ended {
    [[ "$r_pid" =~ ^[0-9]+$ ]] || return 1
    [[ "$r_starttime" =~ ^[0-9]+$ ]] || return 1
    [[ "$(boot_id)" != "$r_bootid" ]] && return 0
    [[ -d "$PROC/$r_pid" ]] || return 0
    [[ "$(proc_starttime "$r_pid")" != "$r_starttime" ]]
}

function do_reconcile {
    local f deleted=0 failed=0 live=0 unknown=0
    lock_records
    for f in "$ACME_STATE_DIR"/inflight/*.rec
    do
        [[ -f "$f" ]] || continue
        read_record "$f"
        if ! [[ "$r_pid" =~ ^[0-9]+$ ]]
        then
            unknown=$((unknown + 1))
            echo "acme-dns-hook: record $r_target ($r_status) has no known certbot owner; not removed" >&2
        elif owner_ended
        then
            if nsupdate_txt delete "$r_target" "$r_value"
            then
                rm -f "$f"
                deleted=$((deleted + 1))
            else
                failed=$((failed + 1))
                echo "acme-dns-hook: retry of $r_target TXT delete ($r_status) failed" >&2
            fi
        else
            live=$((live + 1))
        fi
    done
    unlock_records
    echo "reconcile deleted=$deleted failed=$failed live=$live unknown=$unknown"
}

read_conf
case "${1:-}" in
    auth) do_auth ;;
    cleanup) do_cleanup ;;
    reconcile) do_reconcile ;;
    *) fail "usage: $0 auth|cleanup|reconcile" ;;
esac
