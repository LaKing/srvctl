#!/bin/bash

##
##   modules/named/libs/acmelib.sh — the DNS-01 challenge zone
##   _acme.<company-domain> and its activation, auto-loaded with the named
##   module.
##
##   named_regenerate_activate  hooks/regenerate.sh entry: holds the
##                              activation lock across prepare -> namedcfg ->
##                              restart_named -> manifest commit, so the
##                              DNS-01 zone list always matches the activated
##                              BIND configuration, even when regenerates
##                              overlap. Fails (aborting the regenerate) when
##                              generation, restart or the manifest commit
##                              fails; a prepare problem is reported only.
##   named_prepare_acme_zone    primary: create the TSIG key (tsig-keygen,
##                              hmac-sha256) and the seed zone, each only if
##                              missing (BIND owns the zone file and journal
##                              afterwards). replica: mark the slave zone
##                              enabled only while the primary serves it.
##   named_commit_acme_manifest commit acme-zones.next.json -> acme-zones.json
##                              only when its confSha256 equals the live
##                              srvctl.conf.
##   named_acme_delegation_records
##                              print the company-zone records for review;
##                              nothing here applies them.
##
##   Paths are overridable for the selftests: SC_ACME_KEY_FILE,
##   SC_ACME_SEED_DIR, SC_NAMED_STATE_DIR, SC_NAMED_CONF,
##   SC_NAMED_ACTIVATE_LOCK, SC_CLUSTERS_FILE.
##

## named_acme_topology: rows from topology-cli.js --acme (role, soa,
## primary, replica, host), tab separated.
function named_acme_topology {
    /bin/node "$SC_INSTALL_DIR/modules/named/lib/topology-cli.js" \
        "${SC_CLUSTERS_FILE:-/etc/srvctl/clusters.json}" --acme "$HOSTNAME" "$SC_COMPANY_DOMAIN"
}

## ownership helper, a function so selftests running unprivileged can stub it
function named_acme_chown {
    chown "$@"
}

function named_prepare_acme_zone {
    local rows role soa primary_ip key seeddir seed marker tmp answer
    [[ -n "${SC_COMPANY_DOMAIN:-}" ]] || return 0
    if ! rows="$(named_acme_topology)"
    then
        err "DNS-01: cannot read the DNS topology; the _acme zone is left as it is"
        return 0
    fi
    role="$(awk -F'\t' '$1 == "role" {print $2}' <<< "$rows")"
    soa="$(awk -F'\t' '$1 == "soa" {print $2}' <<< "$rows")"
    primary_ip="$(awk -F'\t' '$1 == "primary" {print $3}' <<< "$rows")"
    key="${SC_ACME_KEY_FILE:-/var/named/srvctl-acme.key}"
    seeddir="${SC_ACME_SEED_DIR:-/var/named/dynamic}"
    seed="$seeddir/_acme.$SC_COMPANY_DOMAIN.zone"
    marker="${SC_NAMED_STATE_DIR:-/var/srvctl3/named}/acme-zone.enabled"

    case "$role" in
        primary)
            if [[ ! -s "$key" ]]
            then
                if ! command -v tsig-keygen > /dev/null 2>&1
                then
                    err "DNS-01: tsig-keygen is missing (bind); the _acme zone stays disabled"
                    return 0
                fi
                tmp="$key.tmp.$$"
                if ( umask 077; tsig-keygen -a hmac-sha256 srvctl-acme > "$tmp" ) && [[ -s "$tmp" ]]
                then
                    named_acme_chown root:named "$tmp"
                    chmod 640 "$tmp"
                    mv -f "$tmp" "$key"
                    msg "DNS-01: created TSIG key $key (hmac-sha256)"
                else
                    rm -f "$tmp"
                    err "DNS-01: tsig-keygen failed; the _acme zone stays disabled"
                    return 0
                fi
            fi
            if [[ ! -e "$seed" ]]
            then
                mkdir -p "$seeddir"
                tmp="$seed.tmp.$$"
                # shellcheck disable=SC2016 # literal $TTL zone-file directive
                printf '%s\n' \
                    "; $SRVCTL generated seed for the DNS-01 challenge zone; BIND owns this file afterwards" \
                    '$TTL 60' \
                    "@        IN SOA        $soa. hostmaster.$SC_COMPANY_DOMAIN. ( 1 15M 5M 1W 60 )" \
                    "        IN         NS        ns1.$SC_COMPANY_DOMAIN." \
                    "        IN         NS        ns2.$SC_COMPANY_DOMAIN." > "$tmp"
                named_acme_chown named:named "$tmp"
                chmod 640 "$tmp"
                mv -f "$tmp" "$seed"
                msg "DNS-01: created seed zone $seed"
            fi
            ;;
        replica)
            ## declare the slave zone only while the primary serves it, so a
            ## replica never fails its transfer check for a missing zone
            answer=""
            if [[ -n "$primary_ip" ]]
            then
                answer="$(dig +time=2 +tries=1 +norecurse +short "@$primary_ip" "_acme.$SC_COMPANY_DOMAIN" SOA 2> /dev/null)"
            fi
            mkdir -p "${marker%/*}"
            if [[ -n "$answer" ]]
            then
                : > "$marker"
            else
                rm -f "$marker"
            fi
            ;;
    esac
    return 0
}

## named_commit_acme_manifest: commit the manifest named.js wrote for the
## configuration that has just been activated. A hash mismatch (the live
## srvctl.conf is not the one the manifest describes) keeps the previous
## manifest and reports it.
function named_commit_acme_manifest {
    local dir next conf want have
    dir="${SC_NAMED_STATE_DIR:-/var/srvctl3/named}"
    next="$dir/acme-zones.next.json"
    conf="${SC_NAMED_CONF:-/var/named/srvctl.conf}"
    [[ -f "$next" ]] || return 0
    want="$(/bin/node -e 'try { process.stdout.write(String(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).confSha256 || "")); } catch (e) {}' "$next")"
    have="$(sha256sum < "$conf" 2> /dev/null)"
    have="${have%% *}"
    if [[ -n "$want" ]] && [[ "$want" == "$have" ]]
    then
        mv -f "$next" "$dir/acme-zones.json"
        return 0
    fi
    err "DNS-01: zone manifest does not match the active BIND configuration; keeping the previous manifest"
    return 1
}

## named_regenerate_activate: the named regenerate hook body.
function named_regenerate_activate {
    local lock fd rc=0
    lock="${SC_NAMED_ACTIVATE_LOCK:-/run/srvctl-named-activate.lock}"
    exec {fd}>> "$lock"
    if ! flock -w "${SC_NAMED_ACTIVATE_WAIT:-900}" "$fd"
    then
        exec {fd}>&-
        err "named activation lock $lock not obtained"
        return 1
    fi

    ## prepare degrades on its own (every failure path reports and returns 0,
    ## leaving the zone as it is); the three steps after it decide the result.
    named_prepare_acme_zone
    if ! namedcfg
    then
        err "named configuration generation failed; BIND is not restarted"
        rc=1
    elif ! restart_named
    then
        rc=1
    elif ! named_commit_acme_manifest
    then
        rc=1
    fi

    flock -u "$fd"
    exec {fd}>&-
    return "$rc"
}

## named_acme_delegation_records: the company-zone records that delegate the
## challenge zone (and, optionally, host names) — printed for review only.
function named_acme_delegation_records {
    local cdn host rows
    cdn="$SC_COMPANY_DOMAIN"
    rows="$(named_acme_topology)" || return 1
    printf '%s\n' \
        "; DNS-01 delegation for review — NOT applied by srvctl." \
        "; Add to the $cdn zone (hand-maintained, included via /var/named/d250.conf) and raise its serial." \
        "_acme                          IN NS    ns1.$cdn." \
        "_acme                          IN NS    ns2.$cdn." \
        "; optional, per configured host name that should get its certificate via DNS-01:"
    while IFS=$'\t' read -r _ host
    do
        [[ "$host" == *".$cdn" ]] || continue
        printf '%-30s IN CNAME %s\n' "_acme-challenge.${host%".$cdn"}" "$host._acme.$cdn."
    done < <(awk -F'\t' '$1 == "host"' <<< "$rows")
}
