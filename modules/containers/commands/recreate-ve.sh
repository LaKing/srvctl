#!/bin/bash

## @@@ recreate-ve VE
## @en Recreate the rootfs
## &en The rootfs is removed, recreated, and user-data restored as good as possible

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

argument container
authorize

if [[ "$(get container "$ARG" exist)" == false ]]
then
    err "Container does not exist."
    exit 0
fi

container_user="$(get container "$ARG" user)"
container_reseller="$(get container "$ARG" reseller)"

msg "Container $ARG - $container_user ($container_reseller)"

if [[ $SC_USER == "$container_user" ]] || [[ $SC_USER == "$container_reseller" ]]
then
    sudomize
fi

C="$ARG"

if [[ -d /srv/"$C"/rootfs/var/lib/mongo ]] || [[ -d /srv/"$C"/rootfs/var/lib/mongodb ]]
then
    ssh "$C" mongodump
fi

run systemctl stop "srvctl-nspawn@$C.service" --no-pager
exif

backup_ve "$C"

tmp_rootfs=/srv/"$C"/tmp_rootfs
if [[ ! -d $tmp_rootfs ]]
then
    msg "Create temporary copy of rootfs"
    run mv /srv/"$C"/rootfs "$tmp_rootfs"
fi


create_nspawn_container_filesystem "$C"



if [[ -d "$tmp_rootfs"/var/www/html/wp-content ]]
then
    
    if run systemctl start "srvctl-nspawn@$C" --no-pager
    then
        
        ssh "$C" 'sc install-wordpress'
        run systemctl stop "srvctl-nspawn@$C.service" --no-pager
        
    fi
    
    #run dnf --installroot=/srv/"$C"/rootfs -y --quiet install wordpress
    rm -fr /srv/"$C"/rootfs/var/lib/mysql/*
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/wp-content /srv/"$C"/rootfs/var/www/html
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/wp-config.php /srv/"$C"/rootfs/var/www/html
    run rsync -a --info=progress2  "$tmp_rootfs"/var/lib/mysql /srv/"$C"/rootfs/var/lib
else
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/* /srv/"$C"/rootfs/var/www/html
fi

run rsync -a --info=progress2  "$tmp_rootfs"/etc/systemd/system/multi-user.target.wants/* /srv/"$C"/rootfs/etc/systemd/system/multi-user.target.wants

run rsync -a --info=progress2  "$tmp_rootfs"/root/dump /srv/"$C"/rootfs/root

if [[ -d "$tmp_rootfs"/root/dump ]]
then
cat > /srv/"$C"/rootfs/etc/yum.repos.d/mongodb.repo << EOF
[Mongodb]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2/mongodb-org/4.2/x86_64/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-4.2.asc
EOF
fi

run rsync -a --info=progress2  "$tmp_rootfs"/var/lib/mongodb /srv/"$C"/rootfs/var/lib
run rsync -a --info=progress2  "$tmp_rootfs"/var/lib/mongo /srv/"$C"/rootfs/var/lib
run rsync -a --info=progress2  "$tmp_rootfs"/srv/* /srv/"$C"/rootfs/srv
run rsync -a --info=progress2  "$tmp_rootfs"/home/* /srv/"$C"/rootfs/home


restore_uids "$C"


#LIST="$( cat /srv/"$C"/rpm.packages.list )"
#
#run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html /srv/"$C"/rootfs/var/www
#run rsync -a --info=progress2  "$tmp_rootfs"/srv /srv/"$C"/rootfs/
#run rsync -a --info=progress2  "$tmp_rootfs"/etc /srv/"$C"/rootfs/
#run rsync -a --info=progress2  "$tmp_rootfs"/home /srv/"$C"/rootfs/
#run rsync -a --info=progress2  "$tmp_rootfs"/root /srv/"$C"/rootfs/
#
#for package in $LIST
#do
#	#msg "dnf check package $package"
#	run dnf --installroot=/srv/"$C"/rootfs -y --quiet install "$package"
#done
#
#run rsync -a --info=progress2  "$tmp_rootfs"/var/lib/mysql /srv/"$C"/rootfs/var/lib
#
if run systemctl start "srvctl-nspawn@$C" --no-pager
then
    sleep 5
    
    run systemctl status "srvctl-nspawn@$C" --no-pager
    
    if [[ -f /srv/"$C"/rootfs/srv/codepad-project/boilerplate/install.sh ]]
    then
        ssh "$C" 'cd /srv/codepad-project/boilerplate && /bin/bash install.sh'
        rm -fr srv/"$C"/rootfs/srv/codepad-project/isolate-*.log
        restore_uids "$C"
        ssh "$C" 'sc mongod restart'
    fi
    
    if [[ -d "$tmp_rootfs"/root/dump ]]
    then
        ssh "$C" 'dnf -y install mongodb-org'
        ssh "$C" 'systemctl enable mongod && systemctl start mongod && systemctl status mongod --no-pager'
        ssh "$C" 'mongorestore'
    fi
    
else
    err "Failed to start container."
    run journalctl -u "srvctl-nspawn@$C" --no-pager
    err "Exiting due to an error."
    exit 17
fi
msg "$C READY"