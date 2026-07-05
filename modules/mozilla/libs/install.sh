#!/bin/bash

## modules/mozilla/libs/install.sh
##
## Loaded by load_libs whenever SC_USE_MOZILLA=true; the single function
## is called only by this module's update-install-host hook.
##
## Provides:
##   install_mozilla_autoconfig
##       Writes /etc/systemd/system/mozilla-autoconfig.service (a root
##       Node.js process serving apps/mozilla-autoconfig-server.js on
##       port 1029 — the haproxy config routes
##       /.well-known/autoconfig/mail/ on hosted domains to it), then
##       daemon-reloads and enables/starts the unit. Idempotent: a rerun
##       rewrites the same unit. Node.js is guaranteed present because
##       update-install installs nodejs before running host hooks.

function install_mozilla_autoconfig {

    msg "Installing mozilla autoconfig"

    ## FIXME(v4): low — Description says "Letsencrypt server.", copy-pasted
    ## from letsencryptlib.sh; misleads operators reading systemctl output.
    ## FIXME(v4): medium — runs as root and the app binds 0.0.0.0:1029,
    ## although the only consumer is haproxy at 127.0.0.1:1029; should be a
    ## dedicated non-root user (cf. letsencrypt's acme user) and localhost bind.
    echo "## $SRVCTL generated
[Unit]
Description=Letsencrypt server.
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/mozilla/apps/mozilla-autoconfig-server.js
User=root
Group=root

Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
    " > /etc/systemd/system/mozilla-autoconfig.service


    systemctl daemon-reload

    run systemctl enable mozilla-autoconfig.service
    run systemctl start mozilla-autoconfig.service
    ## FIXME(v4): low — this status check is the function's (and the sourced
    ## hook's) exit status; if the unit is not active at this instant (e.g.
    ## port 1029 occupied, restart backoff) exif aborts the whole
    ## update-install run, skipping all alphabetically-later module hooks.
    run systemctl status mozilla-autoconfig.service --no-pager
}
