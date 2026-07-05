#!/bin/bash

##
##   containers/hooks/update-install-host.sh — one-time/updating host
##   setup for the container farm.
##
##   Runs via 'run_hooks update-install-host' from 'sc update-install'.
##   Enforces the /srv 0750 contract, installs the limits/sysctl tuning
##   from conf/, the container tooling packages, the
##   srvctl-nspawn@.service template unit (libs/systemlib.sh), the
##   share directories exposed to containers, and the hourly regenerate
##   cron script (whose literal '#cron.hourly' argument triggers the
##   quota check in hooks/regenerate.sh).
##

msg "Containerfarm host installation"

chmod 750 /srv

## set higher limit for using in containers
cat "$SC_INSTALL_DIR/modules/containers/conf/srvctl-limits.conf" > /etc/security/limits.d/srvctl-limits.conf
cat "$SC_INSTALL_DIR/modules/containers/conf/srvctl-sysctl.conf" > /etc/sysctl.d/srvctl-sysctl.conf

## apply settings
sysctl --system

sc_install systemd-container
sc_install debootstrap
sc_install arch-install-scripts

create_srvctl_nspawn_service

run systemctl enable machines.target

mkdir -p /var/srvctl3/share/containers
## FIXME(v4): 'chown 750' uses a mode as owner — the directory ends up
## owned by nonexistent UID 750 instead of being chmod'ed 750.
chown 750 /var/srvctl3/share/containers

mkdir -p /var/srvctl3/share/common
mkdir -p /var/srvctl3/share/lock

{
    echo "#!/bin/bash"
    echo ''
    echo "/bin/bash /usr/local/share/srvctl/srvctl.sh regenerate '#cron.hourly'"
} > /etc/cron.hourly/srvctl-regenerate.sh

chmod +x /etc/cron.hourly/srvctl-regenerate.sh
