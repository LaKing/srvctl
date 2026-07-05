#!/bin/bash

##
##   modules/openvpn/hooks/update-install-host.sh — (re)provisions the
##   OpenVPN hostnet mesh on a cluster host.
##
##   Fired by "run_hooks update-install-host" during "sc update-install".
##   Installs the openvpn package, then obtains the certificates from the
##   srvctl CA: the SC_ROOTCA_HOST mints them all locally
##   (init_openvpn_rootca_certificates), every other host fetches its own
##   over ssh/rsync (grab_openvpn_rootca_certificates) — both in
##   libs/openvpnlib.sh. Generates dh2048.pem once, writes the hostnet
##   server config (udp 1101, tun-hostnet, 10.15.$SC_HOSTNET.1), enables and
##   restarts the server unit under whichever systemd unit layout exists,
##   opens the openvpn-hostnet firewalld service, then writes one client
##   config + unit per other cluster host (tun-host$hs). Config content
##   comes from libs/openvpnconfiglib.sh and must stay byte-identical while
##   the mesh is live.
##
##   Hook contract: must finish with status 0 — run_hook wraps every hook in
##   exif (commonlib.sh), so a non-zero status would abort the whole
##   update-install; hence the explicit "return 0" at the end.
##
##   Deprecation candidate for v4 (G8: zerotier replaces the hostnet mesh),
##   but LIVE on production until the migration.
##

## first install what's necessary
sc_install openvpn

if [[ -z $SC_ROOTCA_HOST ]]
then
    ## NOTE: err + plain return keeps hook status 0 on purpose — hosts that
    ## previously limped through without a CA must still complete
    ## update-install.
    err "SC_ROOTCA_HOST not defined. The openvpn installation can not continue."
    return
fi

run mkdir -p /etc/openvpn

## then get the certificates
if [[ "$SC_ROOTCA_HOST" == "$HOSTNAME" ]]
then
    init_openvpn_rootca_certificates hostnet
    init_openvpn_rootca_certificates usernet
else
    grab_openvpn_rootca_certificates usernet
    grab_openvpn_rootca_certificates hostnet
fi

## FIXME(v4): low — if the glob has no match (e.g. the grab above failed
## because the CA was unreachable) this chmods the literal pattern and
## errors, obscuring the real cause.
run chmod 600 /etc/openvpn/*.key.pem

## generate this for the certificates
if [[ ! -f /etc/openvpn/dh2048.pem ]]
then
    run openssl dhparam -out /etc/openvpn/dh2048.pem 2048
fi

## make the virtual hostnet

if [[ $SC_HOSTNET ]]
then

    write_openvpn_hostnet_server_config

    run chown -R openvpn:openvpn /etc/openvpn

    if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
    then
        run systemctl enable openvpn@hostnet-server.service
        run systemctl restart openvpn@hostnet-server.service
        run systemctl status openvpn@hostnet-server.service --no-pager
    fi

    ## fedora 27 and up
    if [[ -f "/usr/lib/systemd/system/openvpn-server@.service" ]]
    then
        ## FIXME(v4): medium — ln -s without -f is not idempotent: on every
        ## re-run of update-install it fails "File exists" (silently except
        ## stderr, this one is not even run-wrapped); link content stays
        ## correct.
        ln -s /etc/openvpn/hostnet-server.conf /etc/openvpn/server/hostnet-server.conf
        run systemctl enable openvpn-server@hostnet-server.service
        run systemctl restart openvpn-server@hostnet-server.service
        run systemctl status openvpn-server@hostnet-server.service --no-pager
    fi

    firewalld_add_service openvpn-hostnet udp 1101
    ##firewalld_add_service openvpn-usernet tcp 1100

else
    err "Openvpn configuration: SC_HOSTNET undefined"
fi

hostlist="$(get cluster host_list)"

for host in $hostlist
do
    if [[ "$host" == "$HOSTNAME" ]]
    then
        continue
    fi

    ## FIXME(v4): medium — when write_openvpn_client_config bails out
    ## (host_ip or hostnet missing from the datastore) no conf is written,
    ## yet the symlink below is still created (dangling) and the unit
    ## enabled — a permanently failing enabled service on every boot.
    write_openvpn_client_config "$host"
    if [[ -f "/usr/lib/systemd/system/openvpn@.service" ]]
    then
        run systemctl enable "openvpn@hostnet-client-$host.service"
        run systemctl restart "openvpn@hostnet-client-$host.service"
        run systemctl status "openvpn@hostnet-client-$host.service" --no-pager
    fi

    ## fedora 27 and up
    if [[ -f "/usr/lib/systemd/system/openvpn-client@.service" ]]
    then
        ## FIXME(v4): medium — same ln -s idempotency noise as the server
        ## symlink above (fails EEXIST on every re-run).
        ln -s /etc/openvpn/hostnet-client-"$host".conf /etc/openvpn/client/hostnet-client-"$host".conf
        run systemctl enable "openvpn-client@hostnet-client-$host.service"
        ## FIXME(v4): high — unit name typo "cleint": every client tunnel is
        ## enabled, but this restart targets a nonexistent unit, so new or
        ## changed client configs never come up during update-install (only
        ## after reboot or a manual restart), and every run emits a "Unit not
        ## found" warning. Not fixed tonight: correcting it would start
        ## bouncing live tunnels on every update-install.
        run systemctl restart "openvpn-cleint@hostnet-client-$host.service"
        run systemctl status "openvpn-client@hostnet-client-$host.service" --no-pager

        ## FIXME(v4): medium — dead repair attempt: -f on the hostnet-ccd
        ## directory is false so the guard always passes, and the ln always
        ## fails EEXIST because openvpnconfiglib.sh already created a real
        ## /etc/openvpn/server/hostnet-ccd directory — the missing-iroute bug
        ## (see openvpnconfiglib.sh) stays unmitigated, with error noise per
        ## peer host; and being inside the peer loop, a single-host cluster
        ## never even attempts it.
        if [[ ! -f /etc/openvpn/server/hostnet-ccd ]]
        then
            ln -s /etc/openvpn/hostnet-ccd /etc/openvpn/server
        fi
    fi

done

return 0
