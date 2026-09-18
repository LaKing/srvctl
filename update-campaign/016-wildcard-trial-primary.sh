#!/bin/bash
#
# update-campaign/016-wildcard-trial-primary.sh — first live DNS-01 wildcard
# trial, run as root ON THE DNS PRIMARY (r2.d250.hu). Not a srvctl command.
#
# Walks the rollout one phase at a time, asks before every state change and
# verifies every phase. Issuance is a side effect of 'sc regenerate' on the
# primary; this script only sets the two knobs that fence it in
# (SC_ACME_MAX_ISSUE_PER_RUN and SC_ACME_DNS01_ONLY, in /etc/srvctl/acme-trial.conf)
# and runs the regenerates in the right order.
#
#   bash 016-wildcard-trial-primary.sh [options] [phase ...]
#
#   phases (default: all, in this order)
#     preflight   role, binaries, branch, staging flag, public NS of the zone
#     code        git fetch / checkout wildcard-certificates / pull, sc update-install
#     activate    knobs cap=0 + allowlist, sc regenerate: _acme zone, CNAME, manifest
#     secondary   sc regenerate on every replica over root ssh, verify from here
#     issue       knobs cap=1, sc regenerate: the certbot run, bundle, index, TXT cleanup
#     serving     sc regenerate on --serving-host, verify handover and HAProxy SNI
#     status      dump status / index / handover / issue-state for the zone
#     hold        knobs cap=0: freeze issuance, keep everything else as it is
#     open        knobs cap=<n> and allowlist removed: convert every eligible zone
#
#   options
#     --zone <zone>            zone to trial (default flexpont.com)
#     --serving-host <fqdn>    host that serves the zone (for the serving phase)
#     --cap <n>                cap for the open phase (default 3)
#     --yes                    do not ask before state changes
#     -h, --help
#
# Everything printed is also appended to /var/log/srvctl-wildcard-trial.log.

# shellcheck disable=SC2015  # "test && ok || fail" is the intended report idiom: ok/warn/fail never fail
set -u

ZONE="flexpont.com"
SERVING_HOST=""
OPEN_CAP=3
YES=false
PHASES=()
LOGFILE="/var/log/srvctl-wildcard-trial.log"
TRIAL_CONF="/etc/srvctl/acme-trial.conf"
BRANCH="wildcard-certificates"
ACME_DIR="/var/srvctl3/acme"
NAMED_STATE="/var/srvctl3/named"
FAILS=0

while [[ $# -gt 0 ]]
do
    case "$1" in
        --zone) ZONE="$2"; shift 2 ;;
        --serving-host) SERVING_HOST="$2"; shift 2 ;;
        --cap) OPEN_CAP="$2"; shift 2 ;;
        --yes) YES=true; shift ;;
        -h|--help) sed -n '2,32p' "$0" | cut -c3-; exit 0 ;;
        preflight|code|activate|secondary|issue|serving|status|hold|open) PHASES+=("$1"); shift ;;
        *) echo "unknown argument: $1"; exit 2 ;;
    esac
done
[[ ${#PHASES[@]} -gt 0 ]] || PHASES=(preflight code activate secondary issue serving status)
export ZONE

[[ $EUID -eq 0 ]] || { echo "run this as root"; exit 1; }
mkdir -p "$(dirname "$LOGFILE")"
exec > >(tee -a "$LOGFILE") 2>&1
echo "=== $(date -Is) wildcard trial on $HOSTNAME: ${PHASES[*]} (zone $ZONE)"

# --- helpers -------------------------------------------------------------------
say()  { echo "--- $*"; }
ok()   { echo "  [OK]   $*"; }
warn() { echo "  [WARN] $*"; }
fail() { echo "  [FAIL] $*"; FAILS=$((FAILS + 1)); }
die()  { echo "  [ABORT] $*"; exit 1; }

confirm() {
    $YES && return 0
    local answer
    read -r -p ">>> $1 [y/N] " answer
    [[ $answer == y || $answer == Y ]]
}

## json <file> <js-expression over d> — prints the expression or "" (no jq dependency)
json() {
    /bin/node -e '
        let d = null;
        try { d = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")); } catch (e) { process.exit(0); }
        try { const v = eval(process.argv[2]); process.stdout.write(v === undefined || v === null ? "" : (typeof v === "string" ? v : JSON.stringify(v))); } catch (e) {}
    ' "$1" "$2"
}

## the srvctl checkout, company domain and DNS topology of this host
discover() {
    SC_DIR="$(dirname "$(readlink -f /bin/sc)")"
    [[ -f "$SC_DIR/srvctl.sh" ]] || die "cannot find the srvctl checkout behind /bin/sc"
    CDN="$(grep -hoE '^[[:space:]]*SC_COMPANY_DOMAIN=.*' /etc/srvctl/*.conf 2> /dev/null | tail -1 | cut -d= -f2- | tr -d '"'"'"' ')"
    [[ -n $CDN ]] || die "SC_COMPANY_DOMAIN not found in /etc/srvctl/*.conf"
    TOPOLOGY="$(/bin/node "$SC_DIR/modules/named/lib/topology-cli.js" /etc/srvctl/clusters.json --acme "$HOSTNAME" "$CDN")" \
        || die "topology-cli.js --acme failed (is this checkout on the $BRANCH branch?)"
    ROLE="$(awk -F'\t' '$1 == "role" {print $2}' <<< "$TOPOLOGY")"
    PRIMARY_IP="$(awk -F'\t' '$1 == "primary" {print $3}' <<< "$TOPOLOGY")"
    REPLICAS="$(awk -F'\t' '$1 == "replica" {print $2 "\t" $3}' <<< "$TOPOLOGY")"
    echo "srvctl: $SC_DIR  company domain: $CDN  role: $ROLE  primary ip: $PRIMARY_IP"
    [[ -n $REPLICAS ]] && echo "replicas: $(tr '\t\n' ' ,' <<< "$REPLICAS")"
}

## write the trial knobs; cap "" means default, zones "" means no allowlist
set_knobs() {
    local cap="$1" zones="$2"
    {
        echo "## $(date -Is) written by 016-wildcard-trial-primary.sh — DNS-01 rollout fence"
        [[ -n $cap ]] && echo "SC_ACME_MAX_ISSUE_PER_RUN=$cap"
        [[ -n $zones ]] && echo "SC_ACME_DNS01_ONLY=\"$zones\""
    } > "$TRIAL_CONF"
    say "knobs in $TRIAL_CONF:"; grep -v '^##' "$TRIAL_CONF" | sed 's/^/    /'
}

regenerate_here() {
    confirm "run 'sc regenerate' on $HOSTNAME now?" || die "stopped before regenerate"
    say "sc regenerate ($(date -Is))"
    if sc regenerate
    then ok "sc regenerate finished"
    else fail "sc regenerate returned $? — read the output above before continuing"; return 1
    fi
}

cert_report() { ## pem
    local pem="$1"
    openssl x509 -in "$pem" -noout -subject -issuer -dates -ext subjectAltName 2> /dev/null | sed 's/^/    /'
    local ck pk
    ck="$(openssl x509 -in "$pem" -noout -pubkey 2> /dev/null | sha256sum | cut -c1-16)"
    pk="$(openssl pkey -in "$pem" -pubout 2> /dev/null | sha256sum | cut -c1-16)"
    if [[ -n $ck && $ck == "$pk" ]]; then ok "private key matches the certificate"; else fail "private key does not match the certificate"; fi
    if openssl x509 -in "$pem" -noout -issuer 2> /dev/null | grep -qi 'fake\|staging'; then fail "STAGING certificate — never distribute this"; fi
}

# --- phases --------------------------------------------------------------------
phase_preflight() {
    say "preflight"
    [[ $ROLE == primary ]] && ok "this host is the elected DNS primary" || fail "this host is '$ROLE', not the DNS primary — run this on the primary"
    local bin
    for bin in node dig nsupdate tsig-keygen rsync flock openssl sha256sum
    do command -v "$bin" > /dev/null && ok "$bin present" || fail "$bin missing"; done
    if command -v letsencrypt > /dev/null || command -v certbot > /dev/null
    then ok "certbot present"; else fail "neither 'letsencrypt' nor 'certbot' found (sc update-install installs it)"; fi
    [[ -n $REPLICAS ]] && ok "replicas known" || warn "no replica in the topology; the auth hook only waits for the primary"

    if grep -hsE '^[[:space:]]*(export[[:space:]]+)?SC_LETSENCRYPT_STAGING=' /etc/srvctl/*.conf | grep -q true
    then fail "SC_LETSENCRYPT_STAGING=true is set — a test certificate would be distributed and served; remove it"
    else ok "staging flag not set"; fi

    local branch dirty
    branch="$(git -C "$SC_DIR" branch --show-current 2> /dev/null)"
    dirty="$(git -C "$SC_DIR" status --porcelain 2> /dev/null | wc -l)"
    [[ $branch == "$BRANCH" ]] && ok "checkout on $BRANCH" || warn "checkout on '$branch' — the code phase switches to $BRANCH"
    [[ $dirty -eq 0 ]] && ok "checkout clean" || warn "$dirty uncommitted path(s) in $SC_DIR"
    [[ -f "$SC_DIR/modules/letsencrypt/acmerun.js" ]] && ok "DNS-01 code present" || warn "DNS-01 code not present yet (code phase)"

    say "public name servers of $ZONE (via 8.8.8.8, as dns-scan.js sees them)"
    local ns bad=0
    ns="$(dig @8.8.8.8 NS "$ZONE" +short | sort)"
    [[ -n $ns ]] || { fail "no NS answer for $ZONE"; bad=1; }
    while read -r n; do
        [[ -z $n ]] && continue
        case "$n" in "ns1.$CDN."|"ns2.$CDN.") ok "NS $n" ;; *) fail "NS $n is not ns1/ns2.$CDN — the zone would stay on http-01"; bad=1 ;; esac
    done <<< "$ns"
    dig @127.0.0.1 SOA "$ZONE" +short | grep -q . && ok "$ZONE is served by this BIND" || fail "$ZONE has no SOA on this BIND (is it a container domain here?)"
    if [[ $bad -eq 0 ]]; then ok "$ZONE qualifies for DNS-01"; fi

    local h ip
    while IFS=$'\t' read -r h ip; do
        [[ -z $h ]] && continue
        ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$h" true 2> /dev/null && ok "root ssh to replica $h" || warn "no batch root ssh to $h — regenerate it by hand in the secondary phase"
    done <<< "$REPLICAS"
    [[ -n $SERVING_HOST ]] && { ssh -o BatchMode=yes -o ConnectTimeout=5 "root@$SERVING_HOST" true 2> /dev/null && ok "root ssh to $SERVING_HOST" || warn "no batch root ssh to $SERVING_HOST"; }
    [[ -f $TRIAL_CONF ]] && { warn "$TRIAL_CONF already exists:"; grep -v '^##' "$TRIAL_CONF" | sed 's/^/    /'; }
}

phase_code() {
    say "code: $SC_DIR -> $BRANCH"
    confirm "git fetch, checkout $BRANCH and fast-forward pull in $SC_DIR?" || { warn "code phase skipped"; return; }
    git -C "$SC_DIR" fetch origin || die "git fetch failed"
    git -C "$SC_DIR" checkout "$BRANCH" || die "git checkout $BRANCH failed (uncommitted changes?)"
    git -C "$SC_DIR" pull --ff-only || die "git pull failed"
    ok "now at $(git -C "$SC_DIR" log --oneline -1)"
    if confirm "run 'sc update-install' (installs certbot, hook config prerequisites, restarts services)?"
    then sc update-install && ok "update-install finished" || fail "update-install returned non-zero"
    else warn "update-install skipped"; fi
    discover
}

phase_activate() {
    say "activate the _acme.$CDN zone with issuance fenced off (cap 0, allowlist $ZONE)"
    set_knobs 0 "$ZONE"
    regenerate_here || return
    say "verify activation"
    [[ -s /var/named/srvctl-acme.key ]] && ok "TSIG key /var/named/srvctl-acme.key ($(stat -c '%U:%G %a' /var/named/srvctl-acme.key))" || fail "TSIG key missing"
    [[ -e "/var/named/dynamic/_acme.$CDN.zone" ]] && ok "seed zone present" || fail "seed zone /var/named/dynamic/_acme.$CDN.zone missing"
    dig @127.0.0.1 SOA "_acme.$CDN" +short | grep -q . && ok "_acme.$CDN answers on the primary" || fail "_acme.$CDN has no SOA on the primary"
    local cname
    cname="$(dig @127.0.0.1 CNAME "_acme-challenge.$ZONE" +short)"
    [[ $cname == *"._acme.$CDN." ]] && ok "_acme-challenge.$ZONE -> $cname" || fail "_acme-challenge.$ZONE has no challenge CNAME (got '$cname')"
    local manifest="$NAMED_STATE/acme-zones.json"
    [[ -f $manifest ]] && ok "manifest committed: $manifest" || fail "no committed manifest at $manifest"
    [[ "$(json "$manifest" 'd.active')" == true ]] && ok "manifest: _acme zone active" || fail "manifest says the _acme zone is not active"
    local z; z="$(json "$manifest" 'JSON.stringify((d.zones||[]).find(z => z.zone === process.env.ZONE) || null)')"
    [[ -n $z && $z != null ]] && ok "manifest entry: $z" || fail "$ZONE is not in the manifest zone list"
    local live; live="$(sha256sum < /var/named/srvctl.conf | cut -d' ' -f1)"
    [[ "$(json "$manifest" 'd.confSha256')" == "$live" ]] && ok "manifest hash matches the live srvctl.conf" || fail "manifest hash != live srvctl.conf (a regenerate of lag; run it again)"
    [[ -f /etc/letsencrypt/srvctl-acme-dns.conf ]] && ok "hook config written: $(tr '\n' ' ' < /etc/letsencrypt/srvctl-acme-dns.conf)" || warn "hook config not written yet"
    local skipped; skipped="$(json "$ACME_DIR/status.json" 'd.dns01 && d.dns01.skipped')"
    [[ -z $skipped ]] && ok "letsencrypt run reached the DNS-01 phase" || fail "DNS-01 phase skipped: $skipped"
    say "index entry for $ZONE (expected: deferred by the cap)"
    json "$ACME_DIR/bundles/index.json" 'JSON.stringify(d.entries && d.entries[process.env.ZONE], null, 1)'
    echo
}

phase_secondary() {
    say "secondary: every replica must serve _acme.$CDN and the challenge CNAME before the first issuance"
    local h ip
    while IFS=$'\t' read -r h ip; do
        [[ -z $h ]] && continue
        if confirm "run 'sc regenerate' on replica $h over ssh?"
        then ssh -o BatchMode=yes "root@$h" sc regenerate && ok "regenerate on $h finished" || fail "regenerate on $h failed"
        else warn "run 'sc regenerate' on $h by hand, then re-run this phase"; fi
        dig "@$ip" SOA "_acme.$CDN" +short +time=3 +tries=1 | grep -q . && ok "$h ($ip) serves _acme.$CDN" || fail "$h ($ip) does not answer for _acme.$CDN"
        [[ "$(dig "@$ip" CNAME "_acme-challenge.$ZONE" +short +time=3 +tries=1)" == *"._acme.$CDN." ]] && ok "$h serves the challenge CNAME" || fail "$h has no challenge CNAME for $ZONE (zone transfer pending?)"
    done <<< "$REPLICAS"
}

phase_issue() {
    say "issue: cap 1, allowlist $ZONE — this is the live certbot run"
    [[ $FAILS -eq 0 ]] || { confirm "$FAILS check(s) failed so far. Issue anyway?" || die "stopped before issuance"; }
    set_knobs 1 "$ZONE"
    regenerate_here || return
    say "verify issuance"
    local idx="$ACME_DIR/bundles/index.json" pem="$ACME_DIR/bundles/$ZONE.pem"
    local state; state="$(json "$idx" 'd.entries && d.entries[process.env.ZONE] && d.entries[process.env.ZONE].state')"
    echo "  index state: ${state:-<none>}   $(json "$idx" 'JSON.stringify(d.entries && d.entries[process.env.ZONE])')"
    if [[ $state == issued && -s $pem ]]
    then
        ok "bundle published: $pem"
        cert_report "$pem"
        openssl x509 -in "$pem" -noout -ext subjectAltName 2> /dev/null | grep -q "DNS:\*\.$ZONE" && ok "SAN covers *.$ZONE" || fail "SAN does not cover *.$ZONE"
    else
        fail "no issued bundle for $ZONE"
        [[ -f "$ACME_DIR/log/$ZONE.log" ]] && { say "tail of $ACME_DIR/log/$ZONE.log"; tail -40 "$ACME_DIR/log/$ZONE.log"; }
        say "issue-state"; json "$ACME_DIR/issue-state.json" 'JSON.stringify(d[process.env.ZONE])'; echo
    fi
    say "alerts"; json "$ACME_DIR/status.json" 'JSON.stringify(d.alerts || [], null, 1)'; echo
    local txt; txt="$(dig @127.0.0.1 TXT "$ZONE._acme.$CDN" +short)"
    [[ -z $txt ]] && ok "challenge TXT cleaned up" || warn "challenge TXT still present: $txt (reconcile removes it on the next run once certbot has exited)"
    local leftovers=("$ACME_DIR"/hook/*)
    [[ -e ${leftovers[0]} ]] && warn "hook state files left: ${leftovers[*]##*/}" || ok "no stale hook state"
    [[ -f "/var/srvctl3/datastore/cert/wildcard/$ZONE.pem" ]] && ok "primary deployed its own copy to datastore cert/wildcard/$ZONE.pem" || warn "no local wildcard copy (fine if this host serves nothing for $ZONE)"
}

phase_serving() {
    [[ -n $SERVING_HOST ]] || { warn "no --serving-host given; run 'sc regenerate' on the host that serves $ZONE and check /var/srvctl3/acme/handover.json there"; return; }
    say "serving host $SERVING_HOST pulls the bundle and hands over"
    if confirm "run 'sc regenerate' on $SERVING_HOST over ssh?"
    then ssh -o BatchMode=yes "root@$SERVING_HOST" sc regenerate && ok "regenerate on $SERVING_HOST finished" || fail "regenerate on $SERVING_HOST failed"
    else warn "run it by hand, then re-run this phase"; fi
    local st; st="$(ssh -o BatchMode=yes "root@$SERVING_HOST" /bin/node -e "'try{const d=JSON.parse(require(\"fs\").readFileSync(\"$ACME_DIR/handover.json\",\"utf8\"));const e=(d.names||{})[\"$ZONE\"];process.stdout.write(JSON.stringify(e||null))}catch(e){process.stdout.write(\"unreadable\")}'" 2> /dev/null)"
    echo "  handover entry on $SERVING_HOST: ${st:-<none>}"
    [[ $st == *WILDCARD* ]] && ok "state WILDCARD" || fail "state is not WILDCARD yet (a bundle needs a third of its lifetime left and a valid pull; see status.json there)"
    ssh -o BatchMode=yes "root@$SERVING_HOST" test -s "/var/srvctl3/datastore/cert/wildcard/$ZONE.pem" && ok "wildcard bundle installed on $SERVING_HOST" || fail "no cert/wildcard/$ZONE.pem on $SERVING_HOST"
    local name subj
    for name in "$ZONE" "www.$ZONE"
    do
        subj="$(openssl s_client -servername "$name" -connect "$SERVING_HOST:443" < /dev/null 2> /dev/null | openssl x509 -noout -subject 2> /dev/null)"
        [[ $subj == *"CN = *.$ZONE"* || $subj == *"CN=*.$ZONE"* ]] && ok "SNI $name -> $subj" || fail "SNI $name -> ${subj:-no certificate} (expected CN=*.$ZONE)"
    done
}

phase_status() {
    say "status for $ZONE on $HOSTNAME"
    echo "knobs:"; [[ -f $TRIAL_CONF ]] && grep -v '^##' "$TRIAL_CONF" | sed 's/^/    /' || echo "    (no $TRIAL_CONF: cap 10, every eligible zone)"
    echo "dns01:"; json "$ACME_DIR/status.json" 'JSON.stringify(d.dns01, null, 1)'; echo
    echo "index entry:"; json "$ACME_DIR/bundles/index.json" 'JSON.stringify(d.entries && d.entries[process.env.ZONE], null, 1)'; echo
    echo "issue-state:"; json "$ACME_DIR/issue-state.json" 'JSON.stringify(d[process.env.ZONE])'; echo
    echo "alerts:"; json "$ACME_DIR/status.json" 'JSON.stringify(d.alerts || [], null, 1)'; echo
    [[ -s "$ACME_DIR/bundles/$ZONE.pem" ]] && { echo "bundle:"; cert_report "$ACME_DIR/bundles/$ZONE.pem"; }
    echo "all index states:"; json "$ACME_DIR/bundles/index.json" 'Object.entries(d.entries||{}).map(([k,v]) => k + " " + v.state + (v.lastError ? " (" + v.lastError + ")" : "")).join("\n")'; echo
}

phase_hold() {
    say "hold: freeze issuance (cap 0), keep the allowlist and everything already issued"
    confirm "write cap 0 to $TRIAL_CONF?" || return
    set_knobs 0 "$ZONE"
    ok "no certbot call will happen until the cap is raised; installed wildcards stay served"
}

phase_open() {
    say "open: cap $OPEN_CAP per hourly regenerate, no allowlist — converts every eligible zone over time"
    confirm "remove the allowlist and set the cap to $OPEN_CAP?" || return
    set_knobs "$OPEN_CAP" ""
    ok "the next regenerate on the primary issues up to $OPEN_CAP zones; watch $ACME_DIR/status.json"
}

# --- run -----------------------------------------------------------------------
discover
for p in "${PHASES[@]}"
do
    "phase_$p"
    echo
done
if [[ $FAILS -eq 0 ]]
then echo "=== done: all checks passed ($(date -Is))"
else echo "=== done: $FAILS check(s) FAILED — see [FAIL] lines above and $LOGFILE ($(date -Is))"; exit 1
fi
