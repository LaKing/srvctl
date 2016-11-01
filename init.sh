#!/bin/bash

source "$SC_INSTALL_DIR/lablib.sh" || echo "lablib could not be loaded!" 1>&2

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)

## detect virtualization
readonly SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    readonly SC_ON_VE=true
else
    readonly SC_ON_VE=false
fi

SC_ON_HS=false

source /etc/os-release

SC_LOG_DIR=/var/log/srvctl

SC_COMPANY=$HOSTNAME
SC_COMPANY_DOMAIN=$HOSTNAME
SC_ROOT_USERNAME='root'

## containers dir
SRV=/srv
ROOTFS_DIR=/var/srvctl3-rootfs
MOUNTS_DIR=/var/srvctl3-mounts

## source the default values
source "$SC_INSTALL_DIR/config" || echo "Default-config could not be loaded!" 1>&2

## source custom configurations
if [[ -f /etc/srvctl/config ]]
then
    source /etc/srvctl/config
fi


if [[ $USER == root ]] && [[ -z $SUDO_USER ]]
then
    readonly SC_ROOT=true
    readonly SC_USER="$SC_ROOT_USERNAME"
    readonly SC_HOME=~root
else
    if [[ -z $SUDO_USER ]]
    then
        readonly SC_USER="$USER"
        readonly SC_HOME=~
    else
        readonly SC_USER="$SUDO_USER"
        readonly SC_HOME=~$SC_USER
    fi
    readonly SC_ROOT=false
    readonly SC_LOG_DIR=$SC_HOME/.srvct/log
fi


mkdir -p "$SC_LOG_DIR"

## make constants
readonly SC_LOG_DIR
readonly SC_LOG="$SC_LOG_DIR/srvctl.log"
readonly SC_COMPANY
readonly SC_COMPANY_DOMAIN
readonly SC_ON_HS
readonly DEBUG

[ "$CMD" == "?" ] && CMD=status
[ "$CMD" == "+" ] && CMD=start
[ "$CMD" == "-" ] && CMD=stop
[ "$CMD" == "!" ] && CMD=restart

[ "$ARG" == "?" ] && ARG=status
[ "$ARG" == "+" ] && ARG=start
[ "$ARG" == "-" ] && ARG=stop
[ "$ARG" == "!" ] && ARG=restart

readonly SC
readonly CMD="${CMD,,}"
readonly ARG
readonly ARGS
readonly OPA
readonly OPAS
readonly SRV
readonly ROOTFS_DIR
readonly MOUNTS_DIR

## log commands
echo "$NOW [$SC_USER@$HOSTNAME $(pwd)]# $0 $*" >> "$SC_LOG"

## init main lib
source "$SC_INSTALL_DIR/commonlib.sh" || echo "commonlib could not be loaded!" 1>&2


## breakout to help-only
if [[ $CMD == "man" ]] || [[ $CMD == "help" ]] || [[ $CMD == "-help" ]] || [[ $CMD == "--help" ]]
then
    help_commands
    exit
fi
