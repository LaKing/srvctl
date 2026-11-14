#!/bin/bash

## @@@ authorize-user-service USER [SERVICE [off]]
## @en Let a container USER start, stop, restart and reload one SERVICE without root
## &en The user then runs 'systemctl restart SERVICE' itself; no sudo, no password.
## &en Enabling, disabling and every other unit stay root's. Granted with a polkit rule.
## &en Without SERVICE the user's authorized services are listed. 'off' after SERVICE removes it.

## run only with srvctl
[[ $SRVCTL ]] || exit 4

##
##   usersonve/commands/authorize-user-service.sh — per-unit polkit grant.
##
##   Container-only: usersonve is enabled only inside a VE (module condition);
##   ve_only itself is inert. One rule file per user and unit, named so the
##   listing and 'off' find it again. polkitd watches rules.d and reloads on
##   its own, so nothing is restarted here.
##   The user and unit names are checked against strict patterns before they
##   are written into the rule: the rule is JavaScript that polkitd runs.
##   systemctl's verbs for the manage-units action: start, stop, restart,
##   reload, try-restart, reload-or-restart, reload-or-try-restart (systemd
##   dbus-unit.c); enable/disable is a separate action (manage-unit-files).
##

ve_only
root_only

argument user

rules="${SC_POLKIT_RULES_DIR:-/etc/polkit-1/rules.d}" ## test seam
user="$ARG"
[[ $user =~ ^[a-z_][a-z0-9_-]{0,31}$ ]] || { err "Invalid user name: $user"; exit 22; }
id -u "$user" > /dev/null 2>&1 || { err "No such user: $user"; exit 22; }

if [[ -z $OPA ]]
then
    granted="$(grep -h "^// srvctl authorize-user-service $user " "$rules"/60-srvctl-*.rules 2> /dev/null | awk '{print $5}' | paste -sd ' ')"
    msg "Services $user may manage: ${granted:-none}"
    exit 0
fi

unit="$OPA"
[[ $unit == *.* ]] || unit="$unit.service"
[[ $unit =~ ^[A-Za-z0-9][A-Za-z0-9@_.:-]*\.service$ ]] || { err "Invalid service name: $unit"; exit 22; }
file="$rules/60-srvctl-$user-${unit%.service}.rules"

if [[ ${SC_ARGV[3]:-} == off || ${SC_ARGV[3]:-} == none ]]
then
    rm -f "$file"
    msg "$user may no longer manage $unit"
    exit 0
fi

## LoadState, not list-unit-files: that one lists templates (app@.service), not their instances
[[ $(systemctl show -p LoadState --value "$unit" 2> /dev/null) == loaded ]] || { err "No such service: $unit"; exit 22; }

if ! rpm -q polkit > /dev/null 2>&1
then
    run dnf -y -q install polkit || { err "polkit could not be installed"; exit 1; }
fi
## polkit is a static, D-Bus-activated unit: start it, enabling only prints a warning
systemctl is-active -q polkit || run systemctl start polkit

mkdir -p "$rules"
cat > "$file" << EOF
// srvctl authorize-user-service $user $unit
polkit.addRule(function (action, subject) {
    if (action.id == "org.freedesktop.systemd1.manage-units" &&
        action.lookup("unit") == "$unit" &&
        ["start", "stop", "restart", "reload", "try-restart", "reload-or-restart", "reload-or-try-restart"].indexOf(action.lookup("verb")) >= 0 &&
        subject.user == "$user") {
        return polkit.Result.YES;
    }
});
EOF
msg "$user may now start, stop, restart and reload $unit: systemctl restart $unit"
