#!/bin/bash
## Mail of a container handled by another one (container field mail_ve).
## The host side is generated elsewhere: cluster_etc_hosts points mail.<name>
## at the target, so the host postfix (MX) and perdition reach it. This lib
## makes the target's own postfix accept those domains, with two maps that
## srvctl owns completely; main.cf only gets a reference to each, once.
## `@domain @target` keeps the local part: info@band.hu is delivered as
## info@<target>, so the target's /etc/aliases decides (a pipe into an app,
## a mailbox, or an unknown-user bounce).
[[ $SRVCTL ]] || exit 4

: "${SC_MAIL_VE_ROOT:=/srv}"
SC_MAIL_VE_DOMAINS=/etc/postfix/srvctl-mail-ve-domains
SC_MAIL_VE_VIRTUAL=/etc/postfix/srvctl-mail-ve

## Map contents for one target from `get cluster mail_ve_map` lines.
function mail_ve_maps {
    local target="$1" map="$2" t domain
    MAIL_VE_DOMAINS_CONTENT='# srvctl mail_ve'$'\n'
    MAIL_VE_VIRTUAL_CONTENT='# srvctl mail_ve'$'\n'
    while read -r t domain
    do
        [[ $t == "$target" && -n $domain ]] || continue
        MAIL_VE_DOMAINS_CONTENT+="$domain OK"$'\n'
        MAIL_VE_VIRTUAL_CONTENT+="@$domain @$target"$'\n'
    done <<< "$map"
}

## Apply to one target: write the maps owned by its root, add the main.cf
## references, postmap and reload inside the running container. A stopped
## target is left untouched and reported; the next regenerate retries, since
## nothing was written. Unchanged maps with references in place do nothing.
function regenerate_mail_ve {
    local target="$1" map="$2" etc="$SC_MAIL_VE_ROOT/$1/rootfs/etc/postfix" uid
    [[ -f $etc/main.cf ]] || { ntc "mail_ve target $target has no postfix on this host"; return 0; }
    mail_ve_maps "$target" "$map"
    if [[ $(cat "$etc/${SC_MAIL_VE_DOMAINS##*/}" 2> /dev/null)$'\n' == "$MAIL_VE_DOMAINS_CONTENT" &&
          $(cat "$etc/${SC_MAIL_VE_VIRTUAL##*/}" 2> /dev/null)$'\n' == "$MAIL_VE_VIRTUAL_CONTENT" ]] &&
       grep -q "hash:$SC_MAIL_VE_DOMAINS" "$etc/main.cf" && grep -q "hash:$SC_MAIL_VE_VIRTUAL" "$etc/main.cf"
    then
        debug "mail_ve maps unchanged for $target"
        return 0
    fi
    if ! systemctl is-active --quiet "srvctl-nspawn@$target.service"
    then
        ntc "mail_ve: $target is not running; its postfix gets the domains at a later regenerate"
        return 0
    fi
    uid="$(get container "$target" uid)" || return $?
    msg "mail_ve: $target accepts $(grep -c ' OK$' <<< "$MAIL_VE_DOMAINS_CONTENT") domain(s)"
    printf '%s' "$MAIL_VE_DOMAINS_CONTENT" > "$etc/${SC_MAIL_VE_DOMAINS##*/}" || return $?
    printf '%s' "$MAIL_VE_VIRTUAL_CONTENT" > "$etc/${SC_MAIL_VE_VIRTUAL##*/}" || return $?
    ## Host root shows up as nobody in the container; postfix wants root-owned maps.
    chown "$uid:$uid" "$etc/${SC_MAIL_VE_DOMAINS##*/}" "$etc/${SC_MAIL_VE_VIRTUAL##*/}" || return $?
    # shellcheck disable=SC2016 ## expanded inside the container
    systemd-run -M "$target" --wait --pipe --collect --quiet /bin/bash -ec '
        add() { local v; v="$(postconf -h "$1")"; [[ $v == *"hash:$2"* ]] || postconf -e "$1 = ${v:+$v, }hash:$2"; }
        add virtual_alias_domains "$1"
        add virtual_alias_maps "$2"
        postmap "$1"; postmap "$2"
        postfix check
        postfix reload
    ' bash "$SC_MAIL_VE_DOMAINS" "$SC_MAIL_VE_VIRTUAL" < /dev/null
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
    for file in "$SC_MAIL_VE_ROOT"/*/rootfs"$SC_MAIL_VE_VIRTUAL"
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
