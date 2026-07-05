#! /bin/bash
## modules/gui/module-condition.sh - enablement check for the gui module.
## Sourced in a subshell by test_srvctl_modules (commonlib.sh) at init;
## the echoed true/false is cached as SC_USE_GUI in modules.conf.
## Result: false only inside containers, true on every host - even though
## the module is dormant (nothing installs the GUI daemon; only
## libs/spec.sh's make_commands_spec is live). No config toggle, and no
## check that the GUI is actually installed.

SC_VIRT=$(systemd-detect-virt -c)

## lxc is deprecated, but we can consider it a container ofc.
if [[ $SC_VIRT == systemd-nspawn ]] || [[ $SC_VIRT == lxc ]]
then
    echo false
    return
fi

echo true

