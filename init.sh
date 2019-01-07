#!/bin/bash

# shellcheck disable=SC2034
## dynamic source
# shellcheck disable=SC1091
[[ -f /etc/srvctl/debug.conf ]] && source /etc/srvctl/debug.conf

if [[ $USER == root ]]
then
    mkdir -p /etc/srvctl
    mkdir -p /var/local/srvctl
fi

## create startup symlinks for sc and srvctl commands if installed on the standard path
if [[ -f /usr/local/share/srvctl/srvctl.sh ]]
then
    if [[ ! -e /bin/sc ]]
    then
        if [[ -f /usr/bin/sudo ]]
        then
            sudo ln -s /usr/local/share/srvctl/srvctl.sh /bin/sc
        else
            ln -s /usr/local/share/srvctl/srvctl.sh /bin/sc
        fi
    fi
    if [[ ! -e /bin/srvctl ]]
    then
        if [[ -f /usr/bin/sudo ]]
        then
            sudo ln -s /usr/local/share/srvctl/srvctl.sh /bin/srvctl
        else
            ln -s /usr/local/share/srvctl/srvctl.sh /bin/srvctl
        fi
    fi
    ## command completion
    if [[ ! -e /etc/bash_completion.d/srvctl-completion ]]
    then
        if [[ -f /usr/bin/sudo ]]
        then
            sudo ln -s /usr/local/share/srvctl/modules/srvctl/completion.sh /etc/bash_completion.d/srvctl-completion
        else
            ln -s /usr/local/share/srvctl/modules/srvctl/completion.sh /etc/bash_completion.d/srvctl-completion
        fi
    fi
fi

# shellcheck disable=SC2034
SC_LOG=~/.srvctl/srvctl.log
mkdir -p ~/.srvctl

## lablib is mainly for colorization
# shellcheck source=/usr/local/share/srvctl/lablib.sh
source "$SC_INSTALL_DIR/lablib.sh" || echo "lablib could not be loaded!" 1>&2

## init main lib
# shellcheck source=/usr/local/share/srvctl//lablib.sh
source "$SC_INSTALL_DIR/commonlib.sh" || echo "commonlib could not be loaded!" 1>&2

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)
export NOW

if [[ $CMD == update-install ]] || [[ $CMD == 'test-modules' ]]
then
    msg "srvctl test-modules"
    rm -fr /var/local/srvctl/modules.conf
    
    for sourcefile in /etc/srvctl/data/*.conf
    do
        [[ -f $sourcefile ]] && cat "$sourcefile" > /etc/srvctl/"${sourcefile:17}" && debug "@init data -> /etc/srvctl/${sourcefile:17}"
    done
fi


if [[ $CMD == update-install ]]
then
    if [[ -f /bin/node ]]
    then
        debug "Node.JS version $(node --version)"
    else
        dnf -y install nodejs
    fi
    
    ## this is included inline
    if [[ -f /etc/srvctl/data/clusters.json ]] && [[ -f $SC_INSTALL_DIR/modules/containers/host-conf.js ]]
    then
        msg "Configuring host and clusters based on /etc/srvctl/data"
        debug "@init data -> /etc/srvctl/host.conf /etc/srvctl/hosts.json"
        cat /etc/srvctl/data/clusters.json > /etc/srvctl/clusters.json
        /bin/node "$SC_INSTALL_DIR/modules/containers/host-conf.js"
        # shellcheck disable=SC2119
        exif
        # shellcheck disable=SC1091
        source /etc/srvctl/host.conf
        chmod 644 /etc/srvctl/host.conf
        chmod 644 /etc/srvctl/hosts.json
    fi
fi

## LOAD CONFIGs
## source custom configurations
for sourcefile in /etc/srvctl/*.conf
do
    debug "@conf $sourcefile"
    # shellcheck disable=SC1090
    [[ -f $sourcefile ]] && source "$sourcefile"
    
done

source /etc/os-release

if [[ -z $SUDO_USER ]]
then
    readonly SC_USER="$USER"
else
    readonly SC_USER="$SUDO_USER"
fi

if [[ $UID == 0 ]]
then
    readonly SC_ROOT=true
else
    readonly SC_ROOT=false
fi

readonly SC_HOME="$(getent passwd "$SC_USER" | cut -f6 -d:)"
export SC_HOME

debug "UID: $UID USER: $USER SUDO_USER $SUDO_USER SC_USER: $SC_USER SC_ROOT $SC_ROOT"

logs "srvctl $SC_COMMAND_ARGUMENTS"

## log root privileged commands
if [[ $USER == root ]]
then
    echo "$NOW [$SC_USER@$HOSTNAME $(pwd)]# srvctl $SC_COMMAND_ARGUMENTS" >> /var/log/srvctl-root.log
fi

readonly CMD
readonly ARG
readonly ARGS
readonly OPA
readonly OPAS
readonly DEBUG

export SC_USER
export SC_ROOT
export SRVCTL

## load root and user modules
test_srvctl_modules

debug "init@run_hook pre-init"
run_hook "pre-init-$CMD"
run_hook pre-init

## breakout to help-only
if [[ $CMD == "man" ]] || [[ $CMD == "help" ]] || [[ $CMD == "-help" ]] || [[ $CMD == "--help" ]]
then
    help_commands
    exit_0
fi




## load libs for running commands
debug "init@Load libs"
load_libs

## libs loaded, we can run the init hooks of modules
debug "init@run_hook init"
run_hook init

debug "init@run_hook post-init"
run_hook post-init
run_hook "post-init-$CMD"

if [[ $CMD == "complicate" ]]
then
    generate_completion
    msg "srvctl command-completion has been updated for $SC_USER@$HOSTNAME"
    exit_0
fi