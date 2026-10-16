#!/bin/bash

##
##   modules/opendkim/libs/opendkimlib.sh — regenerate DKIM material.
##
##   Sourced by load_libs while the opendkim module is enabled. Provides
##   regenerate_opendkim (called from hooks/regenerate.sh): runs the
##   opendkim.js generator (via opendkim_main), which populates
##   $SC_DATASTORE_DIR/opendkim with per-domain private keys plus the
##   TrustedHosts/KeyTable/SigningTable files; if that folder differs
##   from the runtime copy it is mirrored to /var/opendkim (the location
##   referenced by /etc/opendkim.conf), ownership and permissions are
##   fixed and opendkim.service is restarted — otherwise the service is
##   only started if it is found inactive.
##   Also provides opendkim_conf (written by hooks/update-install-host.sh).
##

## /etc/opendkim.conf. $1 is the private authserv-id of the gateway's own
## milters (MAILAUTH_INTERNAL_ID, postfix libs/mailauthlib.sh): the inbound
## dkim= result is merged into the gateway's single Authentication-Results
## header on the 127.0.0.1:10025 reinjection. Mail is signed for InternalHosts
## and SMTP AUTH clients and verified otherwise; no signing milter runs on
## 10025. Unquoted heredoc on purpose: $SRVCTL expands into the header.
function opendkim_conf {
cat << EOF
#### srvctl $SRVCTL tuned opendkim.conf

## CONFIGURATION OPTIONS
PidFile        /var/run/opendkim/opendkim.pid

##  Selects operating modes. Valid modes are s (sign) and v (verify). Default is v.
Mode        vs


Syslog        yes
SyslogSuccess        yes
LogWhy        yes
UserID        opendkim:opendkim
Socket        inet:8891@127.0.0.1
Umask        002

SendReports        yes
# ReportAddress        "Example.com Postmaster" <postmaster@example.com>

SoftwareHeader        yes

## VERIFYING OPTIONS
AuthservID        $1
AlwaysAddARHeader        yes

## SIGNING OPTIONS
Canonicalization        relaxed/relaxed

Selector        default
MinimumKeyBits        1024

KeyTable        /var/opendkim/KeyTable
SigningTable        refile:/var/opendkim/SigningTable
ExternalIgnoreList        refile:/var/opendkim/TrustedHosts
InternalHosts        refile:/var/opendkim/TrustedHosts

EOF
}

## Set the verifying options of opendkim_conf (authserv-id $1) in the live
## /etc/opendkim.conf ($2 overrides the path for the selftest)
## and restart opendkim when that changed anything. Only these two keys are
## touched: the file may predate the current template and carry local edits.
## mailauth_set_option comes from the postfix module's libs/mailauthlib.sh.
function regenerate_opendkim_conf {
    local file="${2:-/etc/opendkim.conf}" before
    [[ -f $file ]] || return 0
    before="$(cat "$file")"
    mailauth_set_option "$file" AuthservID ' ' "$1"
    mailauth_set_option "$file" AlwaysAddARHeader ' ' yes
    [[ $(cat "$file") == "$before" ]] && return 0
    msg "opendkim.conf: AuthservID $1, AlwaysAddARHeader yes"
    restart_opendkim
}

function regenerate_opendkim {

    msg "regenerate opendkim"

    ## The datastore copy is the cross-host source of truth (on clusters
    ## it may live on the shared gluster datastore); mode 000 keeps the
    ## private keys readable by root only.
    mkdir -p "$SC_DATASTORE_DIR/opendkim"
    chmod 000 "$SC_DATASTORE_DIR/opendkim"
    mkdir -p /var/opendkim

    ## Generate keys and tables into the datastore (aborts srvctl on
    ## failure), then sync the runtime copy only when something changed.
    opendkim_main
    if ! diff -rq /var/opendkim "$SC_DATASTORE_DIR/opendkim" > /dev/null
    then
        ## Runtime copy is stale: replace it wholesale, then set the
        ## permissions opendkim expects — owner opendkim:opendkim,
        ## directories 750, key and table files 640.
        msg "Updating $HOSTNAME opendkim runtime configuration"
        rm -fr /var/opendkim
        cp -R "$SC_DATASTORE_DIR/opendkim" /var
        chown -R opendkim:opendkim /var/opendkim
        chmod -R 750 /var/opendkim
        ## FIXME(v4): low — unquoted glob: when no per-domain key
        ## directories exist yet (fresh cluster) the literal pattern is
        ## passed to chmod, which prints an error; harmless noise only.
        chmod 640 /var/opendkim/*/*
        chmod 640 /var/opendkim/KeyTable
        chmod 640 /var/opendkim/SigningTable
        chmod 640 /var/opendkim/TrustedHosts

        restart_opendkim
    else
        if systemctl is-active opendkim.service > /dev/null
        then
            msg "Configuration for opendkim is up-to-date, opendkim.service running"
        else
            msg "Configuration for opendkim is up-to-date."
            err "opendkim.service is not running!"
            run systemctl start opendkim
            run systemctl enable opendkim
            run systemctl status opendkim --no-pager
        fi
    fi
}
