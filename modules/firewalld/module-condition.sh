#! /bin/bash

#SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
#if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
#then
#    echo false
#    return
#fi

echo true
