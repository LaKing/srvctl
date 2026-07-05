#!/bin/bash

## @@@ update-install HOSTNAME
## @en Run the installation/update script.
## &en Update/Install all components.
## &en On host systems install the containerfarm. and additionally use [HOSTNAME] as additional argument to select a host from a cluster.

root_only

##
##   Install/update flow. Note that this does NOT update the srvctl code
##   itself — code arrives out-of-band (git clone, or /bin/pop on dev boxes).
##   Before this file runs, init.sh has already regenerated /etc/srvctl from
##   /etc/srvctl/data and re-tested all module conditions.
##   Here: full OS dnf update always; then, on a host and only with a
##   HOSTNAME argument: debug.conf, SELinux off, base packages, first-boot
##   hostname (exit 5), git identity, cluster ssh-keyscan, every module's
##   update-install-host hooks, gui command spec, bash completion install,
##   set_permissions. Inside a container only the update-install-ve hooks run.
##

sc_update

if ! $SC_USE_CONTAINERS
then
    ## SC_USE_CONTAINERS is true only on the farm host — this branch
    ## is what runs inside a container (VE)
    run_hooks update-install-ve

    msg "$HOSTNAME update-install complete"
    exit 0
fi

## continue if on the host
if [[ $ARG ]]
then
    msg "Argument $ARG"
else
    ntc "No argument, so we will stop here."
    exit
fi

if [[ ! -f /etc/srvctl/debug.conf ]]
then
    echo "DEBUG=true" > /etc/srvctl/debug.conf
    msg "Debugging turned on - /etc/srvctl/debug.conf"
fi

## disable selinux
## FIXME(v4): replaces the whole config with a single line, dropping
## SELINUXTYPE= (falls back to targeted, but fragile).
msg 'disabling SELinux - needs a reboot for activation'
echo 'SELINUX=disabled' > /etc/selinux/config
## TODO enable it when we are there

## install if we dont have
[[ -f /bin/mc ]] || sc_install mc
[[ -f /bin/node ]] || sc_install nodejs
[[ -f /bin/git ]] || sc_install git


## first-boot path: machine still has the stock hostname
if [[ $HOSTNAME == localhost.localdomain ]]
then

    if [[ $ARG ]]
    then
        msg "setting hostname as $ARG"
        echo "$ARG" > /etc/hostname
    else
        ## FIXME(v4): unreachable — the no-ARG case already exited above,
        ## so this interactive mcedit branch can never run.
        msg "please set a hostname"
        sleep 2
        mcedit /etc/hostname
        cat /etc/hostname
    fi

    msg "after setting a hostname, a reboot is required"
    rm -fr /var/local/srvctl/modules.conf
    ## exit 5 = reboot required; install automation keys off this code
    exit 5
fi

## just some default
git config --global user.name "srvctl"
git config --global user.email "srvctl@$HOSTNAME"

if $SC_USE_CONTAINERS
then
    ## /var/srvctl3/ssh is created but no longer used (its consumer,
    ## a shared known_hosts keyscan, was dropped)
    mkdir -p /var/srvctl3/ssh
    mkdir -p ~/.ssh
    for host in $(get cluster host_list)
    do
        msg "ssh-keyscan $host"
        ## FIXME(v4): appends on every run without deduplication —
        ## ~/.ssh/known_hosts grows unbounded.
        ssh-keyscan "$host" >> ~/.ssh/known_hosts
    done
fi

msg "Calling update-install hooks."
run_hooks update-install-host

if $SC_USE_GUI
then
    make_commands_spec
fi

## for command completion
## bugfix(v4-polish): on a standard install /etc/bash_completion.d/srvctl-completion
## is a SYMLINK back to this module's completion.sh (created by init.sh), so the
## bare redirection below was 'cat X > X': the shell truncated the source file
## through the symlink to 0 bytes, destroying completion and dirtying the
## install-dir git tree. Remove a symlinked destination first so a real copy is
## written. When the destination is already a regular file or absent, the
## [[ -L ]] guard is false and behavior is byte-identical to before; init.sh
## only re-links when the path does not exist, so the copy is not fought over.
[[ -L /etc/bash_completion.d/srvctl-completion ]] && rm -f /etc/bash_completion.d/srvctl-completion
cat "$SC_INSTALL_DIR"/modules/srvctl/completion.sh > /etc/bash_completion.d/srvctl-completion


set_permissions
msg "update-install complete. please reboot."
echo ""
