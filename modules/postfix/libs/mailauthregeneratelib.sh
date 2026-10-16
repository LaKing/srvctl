#!/bin/bash
## Inbound mail authentication on the regenerate path (hooks/regenerate.sh).
##
## Production hosts run only `sc regenerate` (hourly from cron); update-install
## has not run on them for years. So regenerate brings a host to the
## mailauthlib.sh topology by itself: missing packages, the SPF/DMARC/merger
## config (mailauth_install), and the Postfix keys of that topology.
##
## Decision: main.cf and master.cf are NOT re-rendered from conf/ here. Those
## files were rendered long ago and may carry local edits; re-rendering would
## silently drop them. Only the keys listed below are set, with the values
## taken from conf/hs-main.cf and conf/hs-master.cf (postconf reads both
## sides, so the templates stay the single source). Everything else in the
## live files is left alone.
[[ $SRVCTL ]] || exit 4

MAILAUTH_PACKAGES=(pypolicyd-spf-milter python3-pymilter opendmarc publicsuffix-list)
MAILAUTH_MAIN_KEYS=(smtpd_milters non_smtpd_milters milter_default_action header_checks mime_header_checks nested_header_checks)
MAILAUTH_MASTER_KEYS=(smtps/inet/smtpd_milters 127.0.0.1:10025/inet/smtpd_milters 127.0.0.1:10025/inet/receive_override_options)

## Set the MAILAUTH_*_KEYS in the postfix config directory $1 (default
## /etc/postfix) to their template values; prints one line per changed key.
## A master.cf service missing on the host is reported and skipped.
function mailauth_postfix_conf {
    local dir="${1:-/etc/postfix}" tpl key want have
    tpl="$(mktemp -d)"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-main.cf" "$tpl/main.cf"
    cp "$SC_INSTALL_DIR/modules/postfix/conf/hs-master.cf" "$tpl/master.cf"

    for key in "${MAILAUTH_MAIN_KEYS[@]}"
    do
        want="$(postconf -c "$tpl" -h "$key" 2> /dev/null)"
        have="$(postconf -c "$dir" -h "$key" 2> /dev/null)"
        [[ $want == "$have" ]] && continue
        postconf -c "$dir" -e "$key = $want" && echo "main.cf: $key = $want"
    done

    for key in "${MAILAUTH_MASTER_KEYS[@]}"
    do
        if [[ -z $(postconf -c "$dir" -M "${key%/*}" 2> /dev/null) ]]
        then
            err "master.cf has no ${key%/*} service: $key not set."
            continue
        fi
        want="$(postconf -c "$tpl" -P -h "$key" 2> /dev/null)"
        have="$(postconf -c "$dir" -P -h "$key" 2> /dev/null)"
        [[ $want == "$have" ]] && continue
        postconf -c "$dir" -P "$key=$want" && echo "master.cf: $key = $want"
    done

    rm -rf "$tpl"
}

## Called by hooks/regenerate.sh before restart_postfix, which picks up the
## changed main.cf/master.cf. Never fails: mail must keep flowing, and every
## missing piece degrades to "delivered without a gateway header".
function mailauth_regenerate {
    local pkg missing=() line

    [[ -d /etc/postfix ]] || return 0

    for pkg in "${MAILAUTH_PACKAGES[@]}"
    do
        rpm -q "$pkg" > /dev/null 2>&1 || missing+=("$pkg")
    done
    if ((${#missing[@]}))
    then
        sc_install "${missing[@]}" || err "Could not install ${missing[*]}; the next regenerate retries."
    fi

    mailauth_install

    while read -r line
    do
        [[ $line ]] && msg "postfix $line"
    done < <(mailauth_postfix_conf /etc/postfix)
    return 0
}
