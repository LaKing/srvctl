#!/bin/bash

## @@@ limit-ve VE [cpu=PERCENT|default] [memory=SIZE|default] [memory-high=SIZE|default]
## @en Show or set the CPU and memory limits of a container.
## &en Without settings, prints the container's limits (unset means the unit default:
## &en cpu 800%, memory 16G, memory-high 8G). cpu is a percent of one core (200% = 2 cores),
## &en memory sizes take a K/M/G/T suffix. 'default' removes the override.
## &en Limits are stored in the datastore and applied live, without a restart.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   containers/commands/limit-ve.sh — per-container resource limits.
##
##   Writes the cpu_quota / memory_max / memory_high container fields,
##   then apply_container_limits (libs/limitslib.sh) renders the unit
##   drop-in and updates the running unit. All settings are validated
##   before the first datastore write.
##

argument container-name
operators_only
sudomize

C="$ARG"
[[ $(get container "$C" exist) == true ]] || { err "No such container: $C"; exit 22; }

read -ra settings <<< "${OPAS#"$ARG"}"

declare -A new=()
for setting in "${settings[@]}"
do
    key="${setting%%=*}"
    val="${setting#*=}"
    [[ $setting == *=* ]] || { err "Expected KEY=VALUE, got: $setting"; exit 22; }
    case $key in
        cpu)         field=cpu_quota;   valid=container_limits_valid_cpu ;;
        memory)      field=memory_max;  valid=container_limits_valid_memory ;;
        memory-high) field=memory_high; valid=container_limits_valid_memory ;;
        *) err "Unknown limit: $key (cpu, memory, memory-high)"; exit 22 ;;
    esac
    if [[ $val != default ]] && ! "$valid" "$val"
    then
        err "Invalid $key value: $val"; exit 22
    fi
    new[$field]="$val"
done

for field in "${!new[@]}"
do
    if [[ ${new[$field]} == default ]]
    then
        put container "$C" "$field"
    else
        put container "$C" "$field" "${new[$field]}"
    fi
done

if [[ ${#new[@]} -gt 0 ]]
then
    apply_container_limits "$C" || exit $?
fi

read -r cpu max high <<< "$(container_limits_fields "$C")"
[[ $cpu == - ]] && cpu="$SC_VE_DEFAULT_CPU_QUOTA (default)"
[[ $max == - ]] && max="$SC_VE_DEFAULT_MEMORY_MAX (default)"
[[ $high == - ]] && high="$SC_VE_DEFAULT_MEMORY_HIGH (default)"
msg "$C cpu: $cpu, memory: $max, memory-high: $high"
