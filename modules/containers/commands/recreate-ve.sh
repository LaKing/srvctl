#!/bin/bash

## @@@ recreate-ve VE
## @en Recreate the rootfs
## &en The rootfs is removed, recreated, and user-data restored as good as possible

hs_only

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/recreate-ve.sh — rebuild a container's rootfs
##   from the current base image, restoring user data on top.
##
##   Step order and safety net:
##     1. mongodump inside the container if it has mongo data dirs
##     2. stop the unit (exif — abort if the stop fails)
##     3. backup_ve — full rsync backup BEFORE anything is moved
##     4. move the live rootfs aside to /srv/$C/tmp_rootfs, then copy a
##        fresh base image via create_nspawn_container_filesystem
##     5. restore from tmp_rootfs: wordpress branch (boot the fresh VE,
##        'sc install-wordpress', then bring over wp-content, wp-config
##        and the mysql data) or plain /var/www/html copy; then
##        multi-user.target.wants, /root/dump (plus a mongodb.repo so the
##        dump can be restored), mongo data dirs, /srv and /home trees
##     6. restore_uids re-applies datastore-recorded ownership
##     7. start the unit; on success run the codepad boilerplate installer
##        and mongorestore where applicable; exit 17 if the start fails
##
##   The moved-aside tmp_rootfs is deliberately kept as a last-resort
##   rollback copy — but see the FIXME at the mv below.
##

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

## the container owner and its reseller may act as root
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

## FIXME(v4): HIGH — tmp_rootfs is never deleted after a successful run,
## and the mv is skipped when it already exists; a second recreate-ve then
## keeps the CURRENT live rootfs and rsyncs the STALE tmp_rootfs content
## (wp-content, mysql, /srv, /home) over it — silently restoring old data
## over live data.
tmp_rootfs=/srv/"$C"/tmp_rootfs
if [[ ! -d $tmp_rootfs ]]
then
    msg "Create temporary copy of rootfs"
    run mv /srv/"$C"/rootfs "$tmp_rootfs"
fi


create_nspawn_container_filesystem "$C"


## wordpress containers: reinstall wordpress in the fresh rootfs, then
## restore only content, config and database on top
if [[ -d "$tmp_rootfs"/var/www/html/wp-content ]]
then

    if run systemctl start "srvctl-nspawn@$C" --no-pager
    then

        ssh "$C" 'sc install-wordpress'
        run systemctl stop "srvctl-nspawn@$C.service" --no-pager

    fi

    rm -fr /srv/"$C"/rootfs/var/lib/mysql/*
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/wp-content /srv/"$C"/rootfs/var/www/html
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/wp-config.php /srv/"$C"/rootfs/var/www/html
    run rsync -a --info=progress2  "$tmp_rootfs"/var/lib/mysql /srv/"$C"/rootfs/var/lib
else
    run rsync -a --info=progress2  "$tmp_rootfs"/var/www/html/* /srv/"$C"/rootfs/var/www/html
fi

## re-enable the services the old rootfs had enabled
run rsync -a --info=progress2  "$tmp_rootfs"/etc/systemd/system/multi-user.target.wants/* /srv/"$C"/rootfs/etc/systemd/system/multi-user.target.wants

run rsync -a --info=progress2  "$tmp_rootfs"/root/dump /srv/"$C"/rootfs/root

## a mongodump exists: provide the repo so mongodb-org can be reinstalled
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


if run systemctl start "srvctl-nspawn@$C" --no-pager
then
    sleep 5

    run systemctl status "srvctl-nspawn@$C" --no-pager

    ## codepad containers: rerun the boilerplate installer
    if [[ -f /srv/"$C"/rootfs/srv/codepad-project/boilerplate/install.sh ]]
    then
        ssh "$C" 'cd /srv/codepad-project/boilerplate && /bin/bash install.sh'
        ## FIXME(v4): missing leading / — this relative path deletes
        ## nothing (the isolate logs stay in the new rootfs).
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