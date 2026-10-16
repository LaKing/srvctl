#!/bin/bash
## Inbound mail authentication on the gateway: SPF (pyspf-milter), DKIM
## (opendkim module) and DMARC (opendmarc), merged into ONE trusted
## Authentication-Results header whose authserv-id is the gateway host name.
##
## Pass 1 (smtpd 25/465, pickup): cleanup's header_checks drop every incoming
## Authentication-Results and Received-SPF, then the milters run in the order
## of conf/hs-main.cf. They label their results with the private authserv-id
## MAILAUTH_INTERNAL_ID, which amavisd does not touch (it only deletes fields
## carrying its own $myhostname). Pass 2 (amavis -> 127.0.0.1:10025) runs only
## apps/armerge.py: it deletes every Authentication-Results and Received-SPF
## and inserts one "Authentication-Results: <gateway>; spf=..; dkim=..;
## dmarc=.." at the top. No signing milter runs on 10025.
##
## The ports and the header_checks path are also written literally in
## conf/hs-main.cf and conf/hs-master.cf; selftest/mailauth.test.sh keeps
## them in step. MAILAUTH_INTERNAL_ID is also read by the opendkim module's
## update-install-host hook (both modules share the containers condition, so
## this lib is always loaded with it).
[[ $SRVCTL ]] || exit 4

MAILAUTH_INTERNAL_ID=srvctl-internal.invalid
## opendkim's own socket (opendkim module, libs/opendkimlib.sh); listed for the selftest
# shellcheck disable=SC2034
MAILAUTH_DKIM_PORT=8891
MAILAUTH_SPF_PORT=8892
MAILAUTH_DMARC_PORT=8894
MAILAUTH_MERGE_PORT=8895
## Internal clients: not SPF/DMARC-checked as inbound (IPv4/loopback part of mynetworks).
MAILAUTH_INTERNAL_HOSTS=(127.0.0.0/8 ::1 10.0.0.0/8 192.168.0.0/16)

: "${MAILAUTH_HEADER_CHECKS:=/etc/postfix/srvctl-auth-header-checks}"
: "${MAILAUTH_SPF_CONF:=/etc/pyspf-milter/pyspf-milter.conf}"
: "${MAILAUTH_DMARC_CONF:=/etc/opendmarc.conf}"
: "${MAILAUTH_DMARC_IGNORE:=/etc/opendmarc/srvctl-ignore-hosts}"
: "${MAILAUTH_MERGE_UNIT:=/etc/systemd/system/srvctl-armerge.service}"

## The gateway's authserv-id: the canonical host name. Fails unless it is a
## lowercase dotted DNS name.
function mailauth_authserv_id {
    local id="${SC_HOSTNAME:-$HOSTNAME}"
    [[ $id =~ ^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+$ ]] || return 1
    echo "$id"
}

## Every incoming Authentication-Results and Received-SPF is dropped, matched
## on the header name only, so no authserv-id form (quoted, comments,
## quoted-pairs) can slip through to opendmarc or the merger.
function mailauth_header_checks {
    echo '## srvctl: incoming authentication results are never trusted'
    echo '/^Authentication-Results[[:space:]]*:/ IGNORE'
    echo '/^Received-SPF[[:space:]]*:/ IGNORE'
}

function mailauth_ignore_hosts {
    printf '%s\n' "${MAILAUTH_INTERNAL_HOSTS[@]}"
}

## Set KEY to VALUE in a packaged config file: the first uncommented KEY line
## is replaced, later ones dropped, otherwise the line is appended. Keys we
## do not manage (UserID, PidFile, ...) keep the package defaults.
function mailauth_set_option {
    local file="$1" key="$2" sep="$3" value="$4"
    [[ -f $file ]] || : > "$file"
    awk -v key="$key" -v line="$key$sep$value" '
        $1 == key || index($0, key "=") == 1 { if (!done) print line; done = 1; next }
        { print }
        END { if (!done) print line }
    ' "$file" > "$file.srvctl-tmp" && cat "$file.srvctl-tmp" > "$file"
    rm -f "$file.srvctl-tmp"
}

## pyspf-milter: record only (header), reject on hardfail only when
## SC_MAIL_SPF_REJECT_HARDFAIL=true.
function mailauth_configure_spf {
    local file="$1" reject=False hosts
    [[ ${SC_MAIL_SPF_REJECT_HARDFAIL:-} == true ]] && reject=Fail
    hosts="$(IFS=,; echo "${MAILAUTH_INTERNAL_HOSTS[*]}")"
    mailauth_set_option "$file" Socket ' = ' "inet:$MAILAUTH_SPF_PORT@127.0.0.1"
    mailauth_set_option "$file" Header_Type ' = ' AR
    mailauth_set_option "$file" Authserv_Id ' = ' "$MAILAUTH_INTERNAL_ID"
    mailauth_set_option "$file" InternalHosts ' = ' "$hosts"
    mailauth_set_option "$file" skip_addresses ' = ' '127.0.0.0/8,::ffff:127.0.0.0/104,::1'
    mailauth_set_option "$file" PermError_reject ' = ' False
    mailauth_set_option "$file" TempError_Defer ' = ' False
    mailauth_set_option "$file" Mail_From_reject ' = ' "$reject"
    mailauth_set_option "$file" HELO_reject ' = ' "$reject"
}

## opendmarc: record only, honour the sender's policy only when
## SC_MAIL_DMARC_HONOUR_POLICY=true. Trusts only our own milters' results.
function mailauth_configure_opendmarc {
    local file="$1" ignore="$2" reject=false
    [[ ${SC_MAIL_DMARC_HONOUR_POLICY:-} == true ]] && reject=true
    mailauth_set_option "$file" Socket ' ' "inet:$MAILAUTH_DMARC_PORT@127.0.0.1"
    mailauth_set_option "$file" AuthservID ' ' "$MAILAUTH_INTERNAL_ID"
    mailauth_set_option "$file" TrustedAuthservIDs ' ' "$MAILAUTH_INTERNAL_ID"
    mailauth_set_option "$file" IgnoreHosts ' ' "$ignore"
    mailauth_set_option "$file" IgnoreAuthenticatedClients ' ' true
    mailauth_set_option "$file" SPFSelfValidate ' ' false
    mailauth_set_option "$file" FailureReports ' ' false
    mailauth_set_option "$file" PublicSuffixList ' ' /usr/share/publicsuffix/public_suffix_list.dat
    mailauth_set_option "$file" RejectFailures ' ' "$reject"
}

function mailauth_merger_unit {
    cat << EOF
# $SRVCTL
[Unit]
Description=srvctl Authentication-Results merger milter (127.0.0.1:$MAILAUTH_MERGE_PORT)
After=network.target
Before=postfix.service

[Service]
ExecStart=/usr/bin/python3 -I $SC_INSTALL_DIR/modules/postfix/apps/armerge.py --socket inet:$MAILAUTH_MERGE_PORT@127.0.0.1 --authserv-id $1 --internal-id $MAILAUTH_INTERNAL_ID
DynamicUser=yes
Restart=always

[Install]
WantedBy=multi-user.target
EOF
}

## Called by hooks/update-install-host.sh before main.cf/master.cf are
## rendered (main.cf references the header_checks file), and on every
## regenerate by mailauth_regenerate (libs/mailauthregeneratelib.sh). Idempotent.
function mailauth_install {
    local id unit spf dmarc

    msg "Configure inbound mail authentication (SPF, DKIM, DMARC)"
    mailauth_header_checks > "$MAILAUTH_HEADER_CHECKS"

    mkdir -p "${MAILAUTH_SPF_CONF%/*}" "${MAILAUTH_DMARC_IGNORE%/*}"
    spf="$(cat "$MAILAUTH_SPF_CONF" 2> /dev/null || true)"
    dmarc="$(cat "$MAILAUTH_DMARC_CONF" "$MAILAUTH_DMARC_IGNORE" 2> /dev/null || true)"
    mailauth_configure_spf "$MAILAUTH_SPF_CONF"
    mailauth_ignore_hosts > "$MAILAUTH_DMARC_IGNORE"
    mailauth_configure_opendmarc "$MAILAUTH_DMARC_CONF" "$MAILAUTH_DMARC_IGNORE"
    [[ $(cat "$MAILAUTH_SPF_CONF") == "$spf" ]] && spf=false || spf=true
    [[ $(cat "$MAILAUTH_DMARC_CONF" "$MAILAUTH_DMARC_IGNORE") == "$dmarc" ]] && dmarc=false || dmarc=true
    mailauth_service pyspf-milter "$spf"
    mailauth_service opendmarc "$dmarc"

    if ! id="$(mailauth_authserv_id)"
    then
        ## Mail keeps flowing; containers just get no gateway header to trust.
        err "Host name '${SC_HOSTNAME:-$HOSTNAME}' is not a dotted DNS name: the Authentication-Results merger is disabled."
        systemctl disable --now srvctl-armerge.service > /dev/null 2>&1
        return 0
    fi

    unit="$(mailauth_merger_unit "$id")"
    if [[ $(cat "$MAILAUTH_MERGE_UNIT" 2> /dev/null) != "$unit" ]]
    then
        echo "$unit" > "$MAILAUTH_MERGE_UNIT"
        run systemctl daemon-reload
        mailauth_service srvctl-armerge true
    else
        mailauth_service srvctl-armerge false
    fi
}

## Enable NAME.service; restart it when $2 is true or it is not running.
## Regenerate calls this hourly, so an unchanged running service is left alone.
## A missing unit (package not installed) is reported, not fatal: postfix
## skips a dead milter (milter_default_action = accept).
function mailauth_service {
    local unit="$1.service" changed="$2"
    if ! systemctl cat "$unit" > /dev/null 2>&1
    then
        err "$unit is not installed: inbound mail is delivered without its result."
        return 0
    fi
    systemctl is-enabled --quiet "$unit" || run systemctl enable "$unit"
    if [[ $changed == true ]] || ! systemctl is-active --quiet "$unit"
    then
        run systemctl restart "$unit"
    fi
}
