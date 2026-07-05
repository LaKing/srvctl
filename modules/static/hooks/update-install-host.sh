#!/bin/bash

##
##   modules/static/hooks/update-install-host.sh — install the server.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'
##   (modules/srvctl/commands/update-install.sh). Configures the
##   srvctl-storage gluster volume when gluster is in use, then writes,
##   enables and starts /etc/systemd/system/static-server.service: a
##   root-run Node.js fallback file server (server.js) on port 1280,
##   serving /var/srvctl3/storage/static/<host-header>/html.
##
##   G4 (gluster removal): the gluster_configure branch is dead at this
##   commit — the gluster module is hard-disabled, so SC_USE_GLUSTER is
##   never true — and is slated for deletion.
##

## FIXME(v4): 'if $SC_USE_GLUSTER' with an unset variable expands to an
## empty command list = status 0 = true; a stale modules.conf would call
## the undefined gluster_configure.
if $SC_USE_GLUSTER
then
    gluster_configure srvctl-storage /var/srvctl3/storage
fi

## Legacy unit location, superseded by /etc/systemd/system.
## TODO remove after upgrade
rm -fr /usr/lib/systemd/system/static-server.service

## The heredoc is unquoted on purpose: $SC_INSTALL_DIR is expanded at
## generation time, baking the srvctl install path into ExecStart.
## FIXME(v4): runs as root (the sibling default-server runs as nobody)
## while the docroot is derived from the client Host header — see the
## traversal FIXME in server.js.
cat > /etc/systemd/system/static-server.service << EOF
[Unit]
Description=srvctl static server
After=syslog.target network.target

[Service]
Type=simple
ExecStart=/bin/node $SC_INSTALL_DIR/modules/static/server.js
User=root
Group=root
Restart=always

[Install]
WantedBy=multi-user.target
EOF

run systemctl daemon-reload

## Vestigial: the npm installs below are global, nothing here needs cwd.
cd "$SC_INSTALL_DIR/modules/static/" || return

## FIXME(v4): unpinned global npm installs from the network; server.js
## requires them via the hard-coded prefix /usr/lib/node_modules, so a
## different npm prefix or a breaking upstream release turns
## Restart=always into a crash loop. Pin deps in a local package.json.
run npm install -g finalhandler
run npm install -g serve-static

mkdir -p /var/srvctl3/storage/static

## FIXME(v4): nothing routes to port 1280 — haproxy's default backend is
## localhost:1282 (default module) — so this enables a permanently
## running, orphaned root HTTP server on all interfaces; v4 must wire it
## into haproxy as the emergency backend or drop the module (merge with
## the sibling default module).
run systemctl enable static-server.service
run systemctl start static-server.service
run systemctl status static-server.service --no-pager
