#!/bin/bash

###
msg "Containerfarm host installation"

## this option allows machinectl to see our custom machines
#if [[ ! -d /var/lib/containers ]] && [[ ! -f /var/lib/containers ]]
#then
#    run ln -s /srv /var/lib/container
#fi

## set higher limit for using in containers
cat "$SC_INSTALL_DIR/modules/containers/conf/srvctl-limits.conf" > /etc/security/limits.d/srvctl-limits.conf
cat "$SC_INSTALL_DIR/modules/containers/conf/srvctl-sysctl.conf" > /etc/sysctl.d/srvctl-sysctl.conf

sc_install systemd-container

create_srvctl_nspawn_service

run systemctl enable machines.target

mkdir -p /var/srvctl3/share/containers
mkdir -p /var/srvctl3/share/common

{
    echo "#!/bin/bash"
    echo ''
    echo "/bin/bash /usr/local/share/srvctl/srvctl.sh regenerate '#cron.hourly'"
} > /etc/cron.hourly/srvctl-regenerate.sh

chmod +x /etc/cron.hourly/srvctl-regenerate.sh
