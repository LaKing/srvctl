#!/bin/bash
## /etc/cron.hourly/srvctl-regenerate.sh, written by hooks/update-install-host.sh
## and on every regenerate (hooks/regenerate.sh): production hosts never rerun
## update-install, so only regenerate can replace an old copy.
##
## cron mails whatever a job prints to root. A plain regenerate prints ~56 KB
## every hour, which filled /var/mail/root up to postfix's mailbox_size_limit
## (8140 such mails on r2), after which every mail to root bounced. So the
## output goes to a log, and the job prints (and cron mails) only on failure.
[[ $SRVCTL ]] || exit 4

SC_CRON_REGENERATE=/etc/cron.hourly/srvctl-regenerate.sh
SC_CRON_REGENERATE_LOG=/var/log/srvctl-regenerate.log

function cron_regenerate_script {
    echo '#!/bin/bash'
    echo "## $SRVCTL: hourly regenerate. Output: $SC_CRON_REGENERATE_LOG (last run); cron mails root only on failure."
    echo "/bin/bash $SC_INSTALL_DIR/srvctl.sh regenerate '#cron.hourly' > $SC_CRON_REGENERATE_LOG 2>&1 || { echo \"srvctl regenerate failed (exit \$?), output:\"; cat $SC_CRON_REGENERATE_LOG; }"
}

## Rewrites the script only when its content (apart from the version line) changed.
function write_cron_regenerate {
    local file="${1:-$SC_CRON_REGENERATE}" new
    new="$(cron_regenerate_script)"
    if [[ $(grep -v '^## ' "$file" 2> /dev/null) != "$(grep -v '^## ' <<< "$new")" ]]
    then
        echo "$new" > "$file"
        msg "wrote $file (output to $SC_CRON_REGENERATE_LOG, mail only on failure)"
    fi
    chmod +x "$file"
}
