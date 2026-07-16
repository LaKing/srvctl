#!/bin/bash

##
##   modules/named/libs/install.sh — named module lib, auto-loaded when
##   the module is enabled.
##
##   install_named provisions BIND on the host: packages, /etc/named.conf
##   (heredoc procedures live in installnamedlib.sh, sourced on demand),
##   the /var/named skeleton, service enablement and the dns firewall
##   service. Called from hooks/update-install-host.sh; it overwrites
##   /etc/named.conf on every run.
##
##   install_dyndns is DEAD CODE: it returns right after its notice and
##   has no callers anywhere in the tree. The dormant dyndns subsystem it
##   would set up (apps/dyndns-server.js + apps/dyndns-update.sh) has
##   known security issues (see the apps/ headers) and must not be
##   revived as-is.
##

function install_named {

    msg "Installing bind/named DNS server."
    # shellcheck source=/usr/local/share/srvctl/modules/named/installnamedlib.sh
    # shellcheck disable=SC1091 # installed runtime path
    source "$SC_INSTALL_DIR/modules/named/installnamedlib.sh"
    ### procedures defined, now back to running code

    [[ -f /usr/sbin/named ]] || sc_install bind
    ## Replica convergence verification queries authoritative SOAs with dig;
    ## bind-utils is a separate package and may be absent on an existing host
    ## where named itself is already installed.
    [[ -x /usr/bin/dig ]] || sc_install bind-utils
    ## FIXME(v4): medium — ntp/ntpd is retired on current Fedora (chrony
    ## replaced it); the install and enable/start below fail with noisy
    ## errors and no time sync gets configured by this module.
    [[ -f /usr/sbin/ntpd ]] || sc_install ntp

    run systemctl enable ntpd
    run systemctl start ntpd

    ## configure DNS server
    ## no recursion to prevent DNS amplifiaction attacks

    mkdir -p /var/srvctl3/named

    msg "Configure BIND"
    ## DNS needs NTPD enabled and running, otherwise queries may get no response.

    procedure_write_etc_named_conf

    echo "## $SRVCTL generated" > "/var/named/named.conf.local"

    ## FIXME(v4): medium — recent bind packages no longer ship
    ## /usr/share/doc/bind/sample; both rsyncs fail unchecked (no run/exif)
    ## and /etc/named.rfc1912.zones (included by named.conf) is not created.
    rsync -a /usr/share/doc/bind/sample/etc/named.rfc1912.zones /etc
    rsync -a /usr/share/doc/bind/sample/var/named /var
    mkdir -p /var/named/dynamic
    mkdir -p /var/named/srvctl

    chown -R named:named /var/named #?/srvctl
    chmod 750 /var/named/srvctl

    add_service named
    firewalld_add_service dns


}

## DEAD CODE — disabled below and never called; kept only as a reference
## for a possible v4 rebuild (which should use tsig-keygen and validate
## input, see apps/dyndns-server.js header for the security issues).
# shellcheck disable=SC2317 # dormant
function install_dyndns {

    ## dyndns stuff
    ntc "dyndns implementation not ready"
    return

    ## TODO dyndns should be really node user?

    ## FIXME(v4): low (dormant) — $CDN is never defined in any bash scope
    ## (it exists only in named.js), so this tests /etc/srvctl/cert//.key.
    if [[ -f /etc/srvctl/cert/"$CDN/$CDN".key ]] && [[ -f /etc/srvctl/cert/"$CDN/$CDN".crt ]]
    then

        if [[ ! -f /etc/systemd/system/dyndns-server.service ]]
        then
            log "Installing BIND based dyndns."

            mkdir -p /var/dyndns
            chown node:root /var/dyndns
            chmod 754 /var/dyndns

            procedure_write_dyndns_server_service

            systemctl daemon-reload
            systemctl enable dyndns-server
            systemctl start dyndns-server
        fi

        if [ ! -d /var/named/keys ]
        then
            local _this key

            mkdir -p /var/named/keys
            ## FIXME(v4): low (dormant) — dnssec-keygen -a HMAC-MD5 is
            ## unsupported by modern BIND (tsig-keygen replaced it).
            _this="$(dnssec-keygen -K /var/named/keys -r /dev/urandom -a HMAC-MD5 -b 512 -n USER srvctl)"
            cat "/var/named/keys/$_this.key" > /var/named/keys/srvctl.key
            cat "/var/named/keys/$_this.private" > /var/named/keys/srvctl.private

            ## FIXME(v4): low (dormant) — /var/dyndns/srvctl.private is never
            ## created (keys are written under /var/named/keys above).
            chown node /var/dyndns/srvctl.private
            chmod 400 /var/dyndns/srvctl.private

            key="$(grep 'Key: ' "/var/named/keys/$_this.private")"

            procedure_write_named_srvctl_include_key_conf "$key"


            ## use it in dyndns-server
            cat /var/named/srvctl-include-key.conf > /var/dyndns/srvctl-include-key.conf
            chown node:node /var/dyndns/srvctl-include-key.conf
            chmod 400 /var/dyndns/srvctl-include-key.conf

            ## named needs to write to these folders for dyndns
            chown -R named:named /var/named #?/srvctl
            chmod 750 /var/named/srvctl
        fi

    else
        msg "Skipping install for dyndns server due to a lack of certificates: /etc/srvctl/cert/$CDN/$CDN.key /etc/srvctl/cert/$CDN/$CDN.crt"
    fi

}
