#!/bin/bash

## @en List container's statuses

local list
list="$(cfg system container_list)" || exit

echo ''
printf "${YELLOW}%-10s${CLEAR}" "STATUS"
printf "${YELLOW}%-48s${CLEAR}" "HOSTNAME"
printf "${YELLOW}%-14s${CLEAR}" "IP-INTERNAL"
printf "${YELLOW}%-3s${CLEAR}" "IN"
printf "${YELLOW}%-12s${CLEAR}" "HTTP  HTTPS "
printf "${YELLOW}%-4s${CLEAR}" "RES"
printf "${YELLOW}%-3s${CLEAR}" "MX"
printf "${YELLOW}%-5s${CLEAR}" "DISK"
printf "${YELLOW}%-32s${CLEAR}" "USERs"

echo ''

for C in $list
do
    local ip ping_ms
    ip="$(get container "$C" ip)"
    exif "Could not get IP for $C"
    
    if systemctl is-active "$C" > /dev/null
    then
        if ping_ms=$(ping -r -W 1 -c 1 "$ip" | grep rtt)
        then
            printf "${GREEN}%-10s${CLEAR}" "$ping_ms"
        else
            printf "${RED}%-10s${CLEAR}" "ERROR"
        fi
    else
        printf "${RED}%-10s${CLEAR}" "INACTIVE"
    fi
    if [[ -d $SRV/$C ]] && [[ -f /etc/srvctl/containers/$C.service ]]
    then
        printf "${GREEN}%-48s${CLEAR}" "$C"
    else
        printf "${YELLOW}%-48s${CLEAR}" "$C"
    fi
    printf "${GREEN}%-14s${CLEAR}" "$ip"
    echo ''
done

echo ''
