#!/bin/bash

##
##   init.sh — srvctl initialization, sourced by srvctl.sh on every run.
##
##   Order of operations:
##     1. debug.conf, /bin symlink bootstrap, load lablib + commonlib
##     2. update-install/test-modules only: node+git presence and static .conf
##        materialization
##     3. migrate the legacy clusters path and regenerate host-local derived
##        config from the one canonical /etc/srvctl/clusters.json
##     4. source every /etc/srvctl/*.conf, resolve SC_USER/SC_UID0/SC_HOME
##     5. load only module state keyed to the canonical topology generation
##     6. hooks: pre-init-$CMD, pre-init; help breakout; load_libs;
##        init; post-init; post-init-$CMD
##

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
## FIXME(v4): for a non-root user on a box missing these symlinks, every
## invocation attempts 'sudo ln -s' and may hang on a password prompt.
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
    if [[ -d /etc/bash_completion.d ]] && [[ ! -e /etc/bash_completion.d/srvctl-completion ]]
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
# shellcheck source=/usr/local/share/srvctl/commonlib.sh
source "$SC_INSTALL_DIR/commonlib.sh" || echo "commonlib could not be loaded!" 1>&2

## logging related
readonly NOW=$(date +%Y.%m.%d-%H:%M:%S)
export NOW

## Bootstrap path, only for update-install / test-modules: make sure node
## and git exist, then materialize static shell configuration from
## /etc/srvctl/data before the module system initializes. Cluster topology is
## deliberately excluded; /etc/srvctl/clusters.json is its only live path.
if [[ $CMD == update-install ]] || [[ $CMD == test-modules ]]
then
    if [[ -f /bin/node ]]
    then
        debug "Node.JS version $(node --version)"
    else
        msg "NodeJS must be installed."
        run dnf -y install nodejs
        exif
    fi
    
    if [[ -f /bin/git ]]
    then
        debug "Git version $(git --version)"
    else
        msg "Git must be installed."
        run dnf -y install git
        exif
    fi
    
    msg "srvctl test-modules"
    rm -fr /var/local/srvctl/modules.conf
    
    for sourcefile in /etc/srvctl/data/*.conf
    do
        ntc "Processing $sourcefile"
        [[ -f $sourcefile ]] && cat "$sourcefile" > /etc/srvctl/"${sourcefile:17}" && debug "@init data -> /etc/srvctl/${sourcefile:17}"
    done
fi

## Keep the cluster topology single-source and its host-local projections
## current before host.conf (and the other shell configs) are sourced. Root
## reconciles under the shared publisher lock; non-root callers verify the
## canonical and projection hashes under a shared lock and fail if stale.
SC_CLUSTER_HOSTNAME_BOOTSTRAP=false
SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME=
cluster_config_helper="$SC_INSTALL_DIR/modules/containers/lib/cluster-config.sh"
if [[ -f $cluster_config_helper ]]
then
    # shellcheck source=modules/containers/lib/cluster-config.sh
    source "$cluster_config_helper"
    exif "CLUSTER-CONFIG-HELPER"

    if [[ $UID == 0 ]]
    then
        if [[ $CMD == update-install ]] && [[ -n $ARG ]] && \
           [[ $HOSTNAME == localhost.localdomain ]]
        then
            ## Validate and render ARG as the future host, but do not source
            ## its identity before update-install.sh persists /etc/hostname
            ## and exits 5 for the required reboot. Cache this transient run
            ## as generation 'none' so the reboot must recalculate modules.
            prepare_cluster_hostname_bootstrap "$ARG" >/dev/null
            exif "CLUSTER-CONFIG-BOOTSTRAP"
            SC_CANONICAL_CLUSTERS_SHA256=none
            SC_CLUSTER_HOSTNAME_BOOTSTRAP=true
            SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME="$ARG"
        else
            SC_CANONICAL_CLUSTERS_SHA256="$(reconcile_cluster_config)"
            exif "CLUSTER-CONFIG-RECONCILE"
        fi
    else
        SC_CANONICAL_CLUSTERS_SHA256="$(verify_cluster_projection_nonroot)"
        exif "CLUSTER-CONFIG-STALE"
    fi
    readonly SC_CANONICAL_CLUSTERS_SHA256
    ## Exported as the invocation's generation pin: runtime consumers that
    ## reread the canonical topology (host-topology.js, named.js) fail closed
    ## when a publication replaced the generation after this dispatch, instead
    ## of mixing old shell/module state with new topology.
    export SC_CANONICAL_CLUSTERS_SHA256
elif [[ -e /etc/srvctl/clusters.json ]] || [[ -e /etc/srvctl/data/clusters.json ]] || \
     [[ -e /etc/srvctl/host.conf ]] || [[ -e /etc/srvctl/hosts.json ]] || \
     [[ -e /var/srvctl3/host/host.conf ]] || [[ -e /var/srvctl3/host/hosts.json ]]
then
    err "Missing cluster configuration helper: $cluster_config_helper"
    exit 113
fi
readonly SC_CLUSTER_HOSTNAME_BOOTSTRAP
readonly SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME
export SC_CLUSTER_HOSTNAME_BOOTSTRAP
export SC_CLUSTER_BOOTSTRAP_TARGET_HOSTNAME

## An all-host regeneration controller hands every child invocation the
## generation its plan was computed from (SC_EXPECTED_CLUSTERS_SHA256). If
## this host's freshly verified generation differs — a publication landed
## between the controller's probe and this launch — the controller's
## inventory and DNS ordering no longer apply here (an A-primary could be
## launched as a B-replica): refuse before any hook or command runs.
if [[ ${SC_EXPECTED_CLUSTERS_SHA256:-} =~ ^[0-9a-f]{64}$ ]] && \
   [[ $SC_EXPECTED_CLUSTERS_SHA256 != "${SC_CANONICAL_CLUSTERS_SHA256:-none}" ]]
then
    err "Canonical cluster generation differs from the regeneration plan; retry"
    exit 113
fi

## LOAD CONFIGs
## source custom configurations
for sourcefile in /etc/srvctl/*.conf
do
    debug "@conf $sourcefile"
    # shellcheck disable=SC1090
    [[ -f $sourcefile ]] && source "$sourcefile"

done

## host.conf is the generated projection of the canonical cluster topology
## (rendered under /var/srvctl3/host by cluster-config.sh above). It is
## sourced after the static /etc/srvctl configs so the canonical host
## identity cannot be shadowed by a stray static file. During a hostname
## bootstrap the future identity stays unsourced until update-install
## persists the hostname and reboots into it.
sc_host_conf_projection="${SC_CLUSTER_CONFIG_HOST_DIR:-/var/srvctl3/host}/host.conf"
if [[ $SC_CLUSTER_HOSTNAME_BOOTSTRAP == true ]]
then
    debug "@conf deferred until hostname reboot: $sc_host_conf_projection"
elif [[ -f $sc_host_conf_projection ]]
then
    ## A static config that declared one of the projected variables readonly
    ## would silently shadow the canonical identity: the failed assignment
    ## does not abort a sourced file, and later assignments still succeed.
    ## Detect the shadowing and fail closed instead.
    while IFS='=' read -r sc_projected_name _
    do
        [[ $sc_projected_name =~ ^SC_[A-Za-z0-9_]+$ ]] || continue
        if ! (unset "$sc_projected_name" 2>/dev/null)
        then
            err "Readonly $sc_projected_name shadows the generated host.conf"
            exit 113
        fi
    done < "$sc_host_conf_projection"
    debug "@conf $sc_host_conf_projection"
    # shellcheck disable=SC1090
    source "$sc_host_conf_projection"
fi
unset sc_host_conf_projection sc_projected_name

## Detect a publisher commit between releasing the cluster lock and sourcing
## host.conf. The next invocation will read the new coherent generation; this
## invocation must not build or source a cache keyed to mixed generations.
if [[ $SC_CLUSTER_HOSTNAME_BOOTSTRAP != true ]] && \
   [[ -n ${SC_CANONICAL_CLUSTERS_SHA256:-} ]] && \
   [[ ${SC_CLUSTERS_SHA256:-none} != "$SC_CANONICAL_CLUSTERS_SHA256" ]]
then
    err "Canonical cluster generation changed during initialization; retry"
    exit 113
fi

## The sourced-hash check above cannot see a publication that replaced the
## files with generation B while this run sourced the still-old host.conf A
## (A-versus-A passes). Re-probe the raw bytes: canonical must still be the
## verified generation and hosts.json must be the exact projection this
## host.conf was rendered with.
if [[ $SC_CLUSTER_HOSTNAME_BOOTSTRAP != true ]] && \
   [[ ${SC_CANONICAL_CLUSTERS_SHA256:-none} != none ]] && \
   ! cluster_generation_matches "$SC_CANONICAL_CLUSTERS_SHA256" "${SC_HOSTS_SHA256:-}"
then
    err "Canonical cluster generation changed during initialization; retry"
    exit 113
fi

source /etc/os-release

if [[ -z $SUDO_USER ]]
then
    readonly SC_USER="$USER"
else
    readonly SC_USER="$SUDO_USER"
fi

if [[ $UID == 0 ]]
then
    readonly SC_UID0=true
else
    readonly SC_UID0=false
fi

readonly SC_HOME="$(getent passwd "$SC_USER" | cut -f6 -d:)"
export SC_HOME

# echo "debug UID: $UID USER: $USER SUDO_USER $SUDO_USER SC_USER: $SC_USER SC_UID0 $SC_UID0"
# echo "debug: CMD:$CMD ARG:$ARG OPA:$OPA "

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
export SC_UID0
export SRVCTL

## load root and user modules
test_srvctl_modules
exif "MODULE-CONFIG"

## Module conditions consumed hosts.json after the cluster lock was
## released; refuse to continue if a publisher replaced the generation
## mid-selection, so the sourced identity, the module selection, and the
## projection all belong to one canonical generation. The module cache is
## generation-keyed, so the next invocation rebuilds it coherently.
if [[ $SC_CLUSTER_HOSTNAME_BOOTSTRAP != true ]] && \
   [[ ${SC_CANONICAL_CLUSTERS_SHA256:-none} != none ]] && \
   ! cluster_generation_matches "$SC_CANONICAL_CLUSTERS_SHA256" "${SC_HOSTS_SHA256:-}"
then
    err "Canonical cluster generation changed during module selection; retry"
    exit 113
fi

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
