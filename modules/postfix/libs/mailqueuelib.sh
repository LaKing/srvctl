#!/bin/bash
## Host postfix queue by recipient domain. Commands: list-mail-queue,
## show-mail-queue-message, delete-mail-queue-domain. Queue content is
## third-party mail: only metadata is printed unless a message is asked for.
[[ $SRVCTL ]] || exit 4

## One line per queued message with a recipient in DOMAIN (all when empty):
## "<id> <only|mixed> <arrival> <sender> <recipients,...>". "only" means every
## recipient is in DOMAIN. Domain match is exact, case-insensitive.
function mail_queue_select {
    local domain="${1,,}"
    [[ -z $domain || $domain =~ ^[a-z0-9.-]+$ ]] || { err "Invalid domain: $1"; return 22; }
    postqueue -j | /bin/node -e '
        const domain = process.argv[1];
        const mine = (a) => !domain || a.toLowerCase().endsWith("@" + domain);
        for (const line of require("fs").readFileSync(0, "utf8").split("\n")) {
            if (!line.trim()) continue;
            const q = JSON.parse(line);
            const to = (q.recipients || []).map((r) => r.address);
            if (!to.some(mine)) continue;
            const when = new Date((q.arrival_time || 0) * 1000).toISOString().slice(0, 16);
            console.log([q.queue_id, to.every(mine) ? "only" : "mixed", when, q.sender || "<>", to.join(",")].join(" "));
        }' "$domain"
}

function list_mail_queue {
    local rows id scope when sender to subject
    rows="$(mail_queue_select "$1")" || return $?
    [[ -n $rows ]] || { msg "No queued mail${1:+ for $1}"; return 0; }
    while read -r id scope when sender to
    do
        subject="$(postcat -h -q "$id" 2> /dev/null | grep -m1 -i '^Subject:' | cut -c1-100)"
        printf '%s  %s  %s -> %s  %s\n' "$id" "$when" "$sender" "$to" "$subject"
        [[ $scope == only ]] || echo "    (also for other domains)"
    done <<< "$rows"
    msg "$(wc -l <<< "$rows") queued message(s)${1:+ for $1}"
}

## postsuper -d drops a whole message, so one that also goes to another
## domain is kept and reported instead of being lost for those recipients.
function delete_mail_queue_domain {
    local domain="$1" rows ids
    [[ -n $domain ]] || { err "Domain missing"; return 32; }
    rows="$(mail_queue_select "$domain")" || return $?
    ids="$(awk '$2 == "only" { print $1 }' <<< "$rows")"
    awk '$2 == "mixed" { print "kept, also for other domains: " $1 " " $5 }' <<< "$rows"
    [[ -n $ids ]] || { msg "No queued mail only for $domain"; return 0; }
    msg "Delete $(wc -l <<< "$ids") queued message(s) for $domain"
    postsuper -d - <<< "$ids" || return $?
}
