#!/bin/bash
## Mail of a container handled by another one (container field mail_ve).
## The host side is generated elsewhere: cluster_etc_hosts points mail.<name>
## at the target, so the host postfix (MX) and perdition reach it. This lib
## makes the target's own postfix treat those domains as its own: a map that
## srvctl owns completely, referenced once from mydestination.
## mydestination, not a virtual alias: the address stays what was sent,
## pufi@band.hu is delivered as pufi@band.hu (envelope, Delivered-To), and
## the target's /etc/aliases and users decide by the local part. Unknown local
## parts are rejected at SMTP time (local_recipient_maps), not bounced later.
[[ $SRVCTL ]] || exit 4

: "${SC_MAIL_VE_ROOT:=/srv}"
SC_MAIL_VE_DOMAINS=/etc/postfix/srvctl-mail-ve-domains

## Map content for one target from `get cluster mail_ve_map` lines.
function mail_ve_map_content {
    local target="$1" map="$2" t domain
    MAIL_VE_DOMAINS_CONTENT='# srvctl mail_ve'$'\n'
    while read -r t domain
    do
        [[ $t == "$target" && -n $domain ]] || continue
        MAIL_VE_DOMAINS_CONTENT+="$domain OK"$'\n'
    done <<< "$map"
}

## Apply to one target: write the map owned by its root, add the main.cf
## reference, postmap and reload inside the running container. A stopped
## target is left untouched and reported; the next regenerate retries, since
## nothing was written. An unchanged map with the reference in place does nothing.
function regenerate_mail_ve {
    local target="$1" map="$2" etc="$SC_MAIL_VE_ROOT/$1/rootfs/etc/postfix" file uid
    file="$etc/${SC_MAIL_VE_DOMAINS##*/}"
    [[ -f $etc/main.cf ]] || { ntc "mail_ve target $target has no postfix on this host"; return 0; }
    mail_ve_map_content "$target" "$map"
    if [[ $(cat "$file" 2> /dev/null)$'\n' == "$MAIL_VE_DOMAINS_CONTENT" ]] && grep -q "hash:$SC_MAIL_VE_DOMAINS" "$etc/main.cf"
    then
        debug "mail_ve map unchanged for $target"
        return 0
    fi
    if ! systemctl is-active --quiet "srvctl-nspawn@$target.service"
    then
        ntc "mail_ve: $target is not running; its postfix gets the domains at a later regenerate"
        return 0
    fi
    uid="$(get container "$target" uid)" || return $?
    msg "mail_ve: $target accepts $(grep -c ' OK$' <<< "$MAIL_VE_DOMAINS_CONTENT") domain(s) as its own"
    printf '%s' "$MAIL_VE_DOMAINS_CONTENT" > "$file" || return $?
    ## Host root shows up as nobody in the container; postfix wants root-owned maps.
    chown "$uid:$uid" "$file" || return $?
    # shellcheck disable=SC2016 ## expanded inside the container
    systemd-run -M "$target" --wait --pipe --collect --quiet /bin/bash -ec '
        v="$(postconf -h mydestination)"
        [[ $v == *"hash:$1"* ]] || postconf -e "mydestination = ${v:+$v, }hash:$1"
        postmap "$1"
        postfix check
        postfix reload
    ' bash "$SC_MAIL_VE_DOMAINS" < /dev/null
}

## Every mail_ve target on this host, plus former targets whose maps must be
## emptied. Called from hooks/regenerate.sh and set-ve-mail-ve. One failing
## target does not stop the others; the status reports any failure.
function regenerate_mail_ves {
    local map target file status=0
    local -A targets=()
    ## An empty value exits 100 (datastore convention): no mail_ve anywhere.
    map="$(get cluster mail_ve_map)" || { status=$?; [[ $status == 100 ]] || return "$status"; status=0; }
    while read -r target _
    do
        [[ -n $target && -d $SC_MAIL_VE_ROOT/$target/rootfs ]] && targets[$target]=yes
    done <<< "$map"
    for file in "$SC_MAIL_VE_ROOT"/*/rootfs"$SC_MAIL_VE_DOMAINS"
    do
        [[ -f $file ]] || continue
        target="${file#"$SC_MAIL_VE_ROOT/"}"
        targets[${target%%/*}]=yes
    done
    for target in "${!targets[@]}"
    do
        regenerate_mail_ve "$target" "$map" || { err "mail_ve: configuring the postfix of $target failed"; status=1; }
    done
    return "$status"
}
