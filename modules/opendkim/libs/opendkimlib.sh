#!/bin/bash

##
##   modules/opendkim/libs/opendkimlib.sh — regenerate DKIM material.
##
##   Sourced by load_libs while the opendkim module is enabled. Provides
##   regenerate_opendkim (called from hooks/regenerate.sh): runs the
##   opendkim.js generator (via opendkim_main), which populates
##   $SC_DATASTORE_DIR/opendkim with per-domain private keys plus the
##   table files (lib/entitlement.js); if that folder differs
##   from the runtime copy it is mirrored to /var/opendkim (the location
##   referenced by /etc/opendkim.conf), ownership and permissions are
##   fixed and opendkim.service is restarted — otherwise the service is
##   only started if it is found inactive.
##   Also provides regenerate_opendkim_conf (below): the signing policy keys
##   of /etc/opendkim.conf and the Postfix settings it depends on.
##

function regenerate_opendkim {

    msg "regenerate opendkim"

    ## The datastore copy is the cross-host source of truth (on clusters
    ## it may live on the shared gluster datastore); mode 000 keeps the
    ## private keys readable by root only.
    mkdir -p "$SC_DATASTORE_DIR/opendkim"
    chmod 000 "$SC_DATASTORE_DIR/opendkim"
    mkdir -p /var/opendkim

    ## Generate keys and tables into the datastore (aborts srvctl on
    ## failure), then sync the runtime copy only when something changed.
    opendkim_main
    if ! diff -rq /var/opendkim "$SC_DATASTORE_DIR/opendkim" > /dev/null
    then
        ## Runtime copy is stale: replace it wholesale, then set the
        ## permissions opendkim expects — owner opendkim:opendkim,
        ## directories 750, key and table files 640.
        msg "Updating $HOSTNAME opendkim runtime configuration"
        rm -fr /var/opendkim
        cp -R "$SC_DATASTORE_DIR/opendkim" /var
        chown -R opendkim:opendkim /var/opendkim
        chmod -R 750 /var/opendkim
        ## FIXME(v4): low — unquoted glob: when no per-domain key
        ## directories exist yet (fresh cluster) the literal pattern is
        ## passed to chmod, which prints an error; harmless noise only.
        chmod 640 /var/opendkim/*/*
        find /var/opendkim -maxdepth 1 -type f -exec chmod 640 {} +

        restart_opendkim
    else
        if systemctl is-active opendkim.service > /dev/null
        then
            msg "Configuration for opendkim is up-to-date, opendkim.service running"
        else
            msg "Configuration for opendkim is up-to-date."
            err "opendkim.service is not running!"
            run systemctl start opendkim
            run systemctl enable opendkim
            run systemctl status opendkim --no-pager
        fi
    fi
}

## ---------------------------------------------------------------------------
## Signing policy: who may get a signature (documentation.md, OpenDKIM).
##
## The tables (lib/entitlement.js) say which sender may sign which domain; the
## keys of /etc/opendkim.conf and a few Postfix settings decide which senders
## OpenDKIM can tell apart. regenerate_opendkim_conf picks one target:
##   lua        Lua-capable opendkim and every smtpd service passes the SASL
##              login ({auth_authen}): conf/signing-policy.lua decides every
##              signature, the SigningTable is empty.
##   nolua      no Lua (decision 013), or Lua but no smtpd service passes any
##              AUTH macro: OpenDKIM never sees an AUTH session, loopback SMTP
##              gets no milter (smtpd_milter_maps), only pickup (127.0.0.1)
##              signs, from HostSigningTable. Container and AUTH mail unsigned.
##   local-only Lua, but an operator macro setting passes AUTH macros without
##              the login: srvctl gives every smtpd service an empty
##              smtpd_milters override (recorded in srvctl-isolated-listeners)
##              so only pickup reaches OpenDKIM, from HostSigningTable.
##   quiet      the operator routes SMTP milters (H1) or the Postfix config
##              cannot be read: nothing is signed, an err names the setting,
##              Postfix is not touched.
## Every decision reads Postfix values as each smtpd service sees them, with
## $parameter references resolved by srvctl itself; a reference that cannot be
## resolved never counts as safe. Postfix edits only happen after opendkim was
## made quiet, and opendkim leaves quiet only after postfix restarted.
## ---------------------------------------------------------------------------

OPENDKIM_QUIET_MACROS='i {mail_addr} {mail_host} {mail_mailer}'
declare -gA OPENDKIM_PF_MAIN=() OPENDKIM_PF_SVC=() OPENDKIM_PF_PX=() OPENDKIM_PF_CMD=() OPENDKIM_PF_DEF=()
declare -ga OPENDKIM_PF_SIGMA=() OPENDKIM_REASONS=() OPENDKIM_PLAN=() OPENDKIM_ISO_KEEP=()

## opendkim_pf_read <dir> <postconf args...>: stdout in OPENDKIM_PF_OUT; on a
## nonzero exit the error is kept in OPENDKIM_PF_ERR and 1 is returned.
function opendkim_pf_read {
    local dir="$1" errf
    shift
    errf="$(mktemp)"
    if OPENDKIM_PF_OUT="$(postconf -c "$dir" "$@" 2> "$errf")"
    then
        rm -f "$errf"
        return 0
    fi
    OPENDKIM_PF_ERR="postconf $*: $(grep -v 'will be removed' "$errf" | tail -n 2 | tr '\n' ' ')"
    rm -f "$errf"
    return 1
}

## opendkim_pf_load <dir>: read main.cf, the master.cf overrides (raw and as
## postconf expands them) and the services. OPENDKIM_PF_SIGMA: every service
## whose command is smtpd, any type (postscreen setups run it as 'pass'),
## except the *:10025 reinjection (regenerate_reinjection_milters keeps it
## milter-free). Returns 1 when a postconf read fails (the config is
## unreadable, e.g. a $reference cycle); an empty service list is valid.
function opendkim_pf_load {
    local dir="$1" k v line name type cmd
    OPENDKIM_PF_MAIN=() OPENDKIM_PF_SVC=() OPENDKIM_PF_PX=() OPENDKIM_PF_CMD=() OPENDKIM_PF_SIGMA=() OPENDKIM_PF_ERR=''
    while IFS=$'\t' read -r k v
    do
        OPENDKIM_PF_MAIN[$k]="$v"
    done < <(awk '
        function flush() { if (n != "") print n "\t" val; n = "" }
        /^[ \t]*#/ { next }
        /^[ \t]+[^ \t]/ { if (n != "") { s = $0; sub(/^[ \t]+/, "", s); val = val " " s }; next }
        /^[A-Za-z0-9_]+[ \t]*=/ { flush(); n = $0; sub(/[ \t]*=.*/, "", n); val = $0; sub(/^[^=]*=[ \t]*/, "", val); sub(/[ \t]+$/, "", val); next }
        { flush() }
        END { flush() }' "$dir/main.cf")
    opendkim_pf_read "$dir" -P || return 1
    while IFS= read -r line
    do
        [[ $line == *' ='* ]] || continue
        v="${line#* =}"
        OPENDKIM_PF_SVC[${line%% =*}]="${v# }"
    done <<< "$OPENDKIM_PF_OUT"
    opendkim_pf_read "$dir" -Px || return 1
    while IFS= read -r line
    do
        [[ $line == *' ='* ]] || continue
        v="${line#* =}"
        OPENDKIM_PF_PX[${line%% =*}]="${v# }"
    done <<< "$OPENDKIM_PF_OUT"
    opendkim_pf_read "$dir" -M || return 1
    while read -r name type _ _ _ _ _ cmd _
    do
        [[ -n $cmd ]] || continue
        OPENDKIM_PF_CMD[$name/$type]="${cmd##*/}"
        [[ ${cmd##*/} == smtpd && $name != *:10025 ]] && OPENDKIM_PF_SIGMA+=("$name/$type")
    done <<< "$OPENDKIM_PF_OUT"
    return 0
}

## opendkim_pf_lookup <ctx> <name>: the raw value of <name> as service <ctx>
## ("svc/type", or empty for main.cf) sees it: its own -o, then main.cf, then
## the built-in default. Value in OPENDKIM_PF_LV; 1 when it is undefined.
function opendkim_pf_lookup {
    local ctx="$1" name="$2" d
    if [[ -n $ctx && -v OPENDKIM_PF_SVC[$ctx/$name] ]]
    then
        OPENDKIM_PF_LV="${OPENDKIM_PF_SVC[$ctx/$name]}"
        return 0
    fi
    if [[ -v OPENDKIM_PF_MAIN[$name] ]]
    then
        OPENDKIM_PF_LV="${OPENDKIM_PF_MAIN[$name]}"
        return 0
    fi
    if [[ ! -v OPENDKIM_PF_DEF[$name] ]]
    then
        d="$(postconf -d "$name" 2> /dev/null)"
        if [[ $d == "$name ="* ]]
        then
            d="${d#"$name ="}"
            OPENDKIM_PF_DEF[$name]="=${d# }"
        else
            OPENDKIM_PF_DEF[$name]=''
        fi
    fi
    [[ -n ${OPENDKIM_PF_DEF[$name]} ]] || return 1
    OPENDKIM_PF_LV="${OPENDKIM_PF_DEF[$name]#=}"
}

## opendkim_pf_expand <ctx> <text> <depth> <chain>: srvctl's own expansion of
## $name and ${name}; anything else (conditional forms, $(..), $$), an
## undefined name, a cycle or nesting deeper than 8 is unresolved (returns 1,
## reason in OPENDKIM_PF_WHY). Result in OPENDKIM_PF_EXP.
function opendkim_pf_expand {
    local ctx="$1" rest="$2" depth="$3" chain="$4" out="" name
    while [[ $rest == *'$'* ]]
    do
        out+="${rest%%\$*}"
        rest="${rest#*\$}"
        if [[ $rest =~ ^\{([A-Za-z0-9_]+)\}(.*)$ ]] || [[ $rest =~ ^([A-Za-z0-9_]+)(.*)$ ]]
        then
            name="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
        else
            OPENDKIM_PF_WHY="unsupported expansion form near \$${rest:0:12}"
            return 1
        fi
        if [[ " $chain " == *" $name "* ]]
        then
            OPENDKIM_PF_WHY="cycle through \$$name"
            return 1
        fi
        if (( depth >= 8 ))
        then
            OPENDKIM_PF_WHY="nesting deeper than 8 at \$$name"
            return 1
        fi
        if ! opendkim_pf_lookup "$ctx" "$name"
        then
            OPENDKIM_PF_WHY="undefined parameter \$$name${ctx:+ in $ctx}"
            return 1
        fi
        opendkim_pf_expand "$ctx" "$OPENDKIM_PF_LV" $((depth + 1)) "$chain $name" || return 1
        out+="$OPENDKIM_PF_EXP"
    done
    OPENDKIM_PF_EXP="$out$rest"
}

## opendkim_pf_eval <ctx> <name>: the effective value of <name> in service
## <ctx>. OPENDKIM_PF_STATE ok|unresolved, OPENDKIM_PF_VALUE, OPENDKIM_PF_WHY,
## OPENDKIM_PF_RAW (the value as written). A direct override must expand the
## way postconf -Px expands it, or it is unresolved.
function opendkim_pf_eval {
    local ctx="$1" name="$2"
    OPENDKIM_PF_STATE=unresolved OPENDKIM_PF_VALUE='' OPENDKIM_PF_WHY='' OPENDKIM_PF_RAW=''
    if ! opendkim_pf_lookup "$ctx" "$name"
    then
        OPENDKIM_PF_STATE=ok
        return 0
    fi
    OPENDKIM_PF_RAW="$OPENDKIM_PF_LV"
    opendkim_pf_expand "$ctx" "$OPENDKIM_PF_LV" 0 "$name" || return 0
    if [[ -n $ctx && -v OPENDKIM_PF_SVC[$ctx/$name] && ${OPENDKIM_PF_PX[$ctx/$name]} != "$OPENDKIM_PF_EXP" ]]
    then
        OPENDKIM_PF_WHY="postconf expands $ctx/$name differently"
        return 0
    fi
    OPENDKIM_PF_STATE=ok OPENDKIM_PF_VALUE="$OPENDKIM_PF_EXP"
}

## Predicates over the last opendkim_pf_eval: an unresolved value is never safe.
function opendkim_has_authen { [[ $OPENDKIM_PF_STATE == ok && $OPENDKIM_PF_VALUE == *'{auth_authen}'* ]]; }
function opendkim_no_auth { [[ $OPENDKIM_PF_STATE == ok && $OPENDKIM_PF_VALUE != *'{auth_'* ]]; }
function opendkim_reaches { [[ $OPENDKIM_PF_STATE != ok || $OPENDKIM_PF_VALUE == *:8891* ]]; }
function opendkim_pf_desc {
    if [[ $OPENDKIM_PF_STATE == ok ]]
    then
        echo "'$OPENDKIM_PF_RAW' (= '$OPENDKIM_PF_VALUE')"
    else
        echo "'$OPENDKIM_PF_RAW' cannot be resolved ($OPENDKIM_PF_WHY)"
    fi
}

## opendkim_iso_revalidate <dir>: keep a recorded srvctl override only while
## its service still runs smtpd and the override still has the empty value
## srvctl wrote; a changed or removed one is dropped from the record and is
## the operator's from then on. Kept entries in OPENDKIM_ISO_KEEP.
function opendkim_iso_revalidate {
    local dir="$1" iso="$1/srvctl-isolated-listeners" s
    local -a keep=()
    OPENDKIM_ISO_KEEP=()
    [[ -f $iso ]] || return 0
    while read -r s
    do
        [[ -n $s ]] || continue
        if [[ ${OPENDKIM_PF_CMD[$s]:-} == smtpd && -v OPENDKIM_PF_SVC[$s/smtpd_milters] && -z ${OPENDKIM_PF_SVC[$s/smtpd_milters]} ]]
        then
            keep+=("$s")
        else
            msg "opendkim: $s smtpd_milters is no longer srvctl's empty override; it counts as the operator's"
        fi
    done < "$iso"
    OPENDKIM_ISO_KEEP=("${keep[@]}")
    opendkim_iso_write "$dir" "${keep[@]}"
}

function opendkim_iso_write { # dir entries...
    local iso="$1/srvctl-isolated-listeners" want
    shift
    want="$(printf '%s\n' "$@" | sed '/^$/d' | sort -u)"
    if [[ -z $want ]]
    then
        rm -f "$iso"
    elif [[ $(cat "$iso" 2> /dev/null) != "$want" ]]
    then
        echo "$want" > "$iso"
    fi
}

function opendkim_map_text {
    printf '%s\n' '## srvctl (opendkim module): no milter for SMTP sessions from loopback' '127.0.0.0/8 DISABLE' '::1/128 DISABLE'
}

## opendkim_plan_apply <dir> live|copy: run OPENDKIM_PLAN. Entries are
## tab-separated: 'pc <postconf args...>', 'map', 'iso+ <svc>', 'iso- <svc>'.
## On a copy (rehearsal) only the postconf commands run.
function opendkim_plan_apply {
    local dir="$1" mode="$2" op line iso
    local -a a
    for line in "${OPENDKIM_PLAN[@]}"
    do
        IFS=$'\t' read -r -a a <<< "$line"
        op="${a[0]}"
        case "$op" in
            pc)
                postconf -c "$dir" "${a[@]:1}" 2> /dev/null || { err "opendkim: postconf ${a[*]:1} failed in $dir"; return 1; }
                [[ $mode == live ]] && msg "opendkim: postfix: postconf ${a[*]:1}"
                ;;
            map)
                [[ $mode == live ]] || continue
                opendkim_map_text > "$dir/srvctl-milter-map" || return 1
                msg "opendkim: postfix: wrote $dir/srvctl-milter-map"
                ;;
            iso+|iso-)
                [[ $mode == live ]] || continue
                iso="$(cat "$dir/srvctl-isolated-listeners" 2> /dev/null)"
                if [[ $op == iso+ ]]
                then
                    # shellcheck disable=SC2086 # one entry per line
                    opendkim_iso_write "$dir" $iso "${a[1]}"
                else
                    # shellcheck disable=SC2046,SC2086
                    opendkim_iso_write "$dir" $(grep -vxF "${a[1]}" <<< "$iso")
                fi
                ;;
        esac
    done
    return 0
}

## opendkim_neutral_check <dir> <map>: on (a copy of) a config, as it really
## is: every smtpd service passes no AUTH macro, no service overrides
## smtpd_milter_maps, main.cf has srvctl's map. Unsafe settings in
## OPENDKIM_UNSAFE.
function opendkim_neutral_check {
    local dir="$1" map="$2" s
    OPENDKIM_UNSAFE=
    opendkim_pf_load "$dir" || { OPENDKIM_UNSAFE=" $OPENDKIM_PF_ERR"; return 1; }
    for s in "${OPENDKIM_PF_SIGMA[@]}"
    do
        opendkim_pf_eval "$s" milter_mail_macros
        opendkim_no_auth || OPENDKIM_UNSAFE+=" $s milter_mail_macros $(opendkim_pf_desc);"
        [[ -v OPENDKIM_PF_SVC[$s/smtpd_milter_maps] ]] && OPENDKIM_UNSAFE+=" $s smtpd_milter_maps;"
    done
    [[ ${OPENDKIM_PF_MAIN[smtpd_milter_maps]:-} == "$map" ]] || OPENDKIM_UNSAFE+=" main.cf smtpd_milter_maps;"
    [[ -z $OPENDKIM_UNSAFE ]]
}

## opendkim_neutralise_plan <dir> <map>: case D (no Lua). Plan the edits that
## stop every AUTH macro from reaching opendkim, rehearse them on a copy and
## check the result as it really is; if an inherited operator
## milter_mail_macros is still exposed, add M and check again. The checked
## plan is left in OPENDKIM_PLAN (the live directory is not touched);
## returns 1 when it cannot be made safe.
function opendkim_neutralise_plan {
    local dir="$1" map="$2" m="$OPENDKIM_QUIET_MACROS" s copy v_unset=false ok=0
    OPENDKIM_PLAN=()
    for s in "${OPENDKIM_PF_SIGMA[@]}"
    do
        if [[ -v OPENDKIM_PF_SVC[$s/milter_mail_macros] ]]
        then
            opendkim_pf_eval "$s" milter_mail_macros
            opendkim_no_auth || OPENDKIM_PLAN+=("pc"$'\t'"-PX"$'\t'"$s/milter_mail_macros")
        fi
        [[ -v OPENDKIM_PF_SVC[$s/smtpd_milter_maps] ]] && OPENDKIM_PLAN+=("pc"$'\t'"-PX"$'\t'"$s/smtpd_milter_maps")
    done
    [[ $(cat "$dir/srvctl-milter-map" 2> /dev/null) == "$(opendkim_map_text)" ]] || OPENDKIM_PLAN+=("map")
    [[ ${OPENDKIM_PF_MAIN[smtpd_milter_maps]:-} == "$map" ]] || OPENDKIM_PLAN+=("pc"$'\t'"-e"$'\t'"smtpd_milter_maps = $map")
    if [[ ! -v OPENDKIM_PF_MAIN[milter_mail_macros] ]]
    then
        v_unset=true
        OPENDKIM_PLAN+=("pc"$'\t'"-e"$'\t'"milter_mail_macros = $m")
    fi
    for s in "${OPENDKIM_ISO_KEEP[@]}"
    do
        OPENDKIM_PLAN+=("pc"$'\t'"-PX"$'\t'"$s/smtpd_milters" "iso-"$'\t'"$s")
    done
    copy="$(mktemp -d)"
    cp "$dir/main.cf" "$dir/master.cf" "$copy/"
    opendkim_plan_apply "$copy" copy || ok=1
    if (( ok == 0 )) && ! opendkim_neutral_check "$copy" "$map"
    then
        if $v_unset
        then
            ok=1
        else
            OPENDKIM_PLAN+=("pc"$'\t'"-e"$'\t'"milter_mail_macros = $m")
            postconf -c "$copy" -e "milter_mail_macros = $m" 2> /dev/null
            opendkim_neutral_check "$copy" "$map" || ok=1
        fi
    fi
    rm -rf "$copy"
    return "$ok"
}

## opendkim_classify <dir>: pick the target (OPENDKIM_TARGET, OPENDKIM_CASE),
## the reasons to report (OPENDKIM_REASONS) and the Postfix plan
## (OPENDKIM_PLAN), all from the configuration as it is before any edit.
## srvctl's own values (M, the map, recorded empty overrides) count as undone,
## so its edits never change the next run's decision.
function opendkim_classify {
    local dir="$1" m="$OPENDKIM_QUIET_MACROS" map="cidr:$1/srvctl-milter-map" def s lua=false
    local v_owned=false w_owned=false all_authen=true b_ok=true inh
    local -a hide=() reach=() wsvc=()
    OPENDKIM_REASONS=() OPENDKIM_PLAN=() OPENDKIM_ISO_KEEP=()
    if ! opendkim_pf_load "$dir"
    then
        OPENDKIM_CASE=Z OPENDKIM_TARGET=quiet
        OPENDKIM_REASONS=("postfix configuration in $dir cannot be read: $OPENDKIM_PF_ERR")
        return 0
    fi
    opendkim_iso_revalidate "$dir"
    "${SC_OPENDKIM_BIN:-opendkim}" -V 2>&1 | grep -q USE_LUA && lua=true
    [[ ! -v OPENDKIM_PF_MAIN[milter_mail_macros] || ${OPENDKIM_PF_MAIN[milter_mail_macros]} == "$m" ]] && v_owned=true
    [[ ! -v OPENDKIM_PF_MAIN[smtpd_milter_maps] || ${OPENDKIM_PF_MAIN[smtpd_milter_maps]} == "$map" ]] && w_owned=true
    def="$(postconf -d -h milter_mail_macros 2> /dev/null)"
    for s in "${OPENDKIM_PF_SIGMA[@]}"
    do
        if [[ ! -v OPENDKIM_PF_SVC[$s/milter_mail_macros] ]] && $v_owned
        then
            inh=true OPENDKIM_PF_STATE=ok OPENDKIM_PF_VALUE="$def" OPENDKIM_PF_RAW="$def"
        else
            inh=false
            opendkim_pf_eval "$s" milter_mail_macros
        fi
        opendkim_has_authen || { all_authen=false; hide+=("$s milter_mail_macros $(opendkim_pf_desc)"); }
        $inh || opendkim_no_auth || b_ok=false
        [[ -v OPENDKIM_PF_SVC[$s/smtpd_milter_maps] ]] && wsvc+=("$s smtpd_milter_maps '${OPENDKIM_PF_SVC[$s/smtpd_milter_maps]}' overrides the milter routing")
        if [[ -v OPENDKIM_PF_SVC[$s/smtpd_milters] && " ${OPENDKIM_ISO_KEEP[*]} " != *" $s "* ]]
        then
            opendkim_pf_eval "$s" smtpd_milters
            opendkim_reaches && reach+=("$s smtpd_milters $(opendkim_pf_desc) reaches opendkim")
        fi
    done
    $w_owned || wsvc+=("main.cf smtpd_milter_maps '${OPENDKIM_PF_MAIN[smtpd_milter_maps]}' is operator-set and routes SMTP milters")

    if ! $lua
    then
        OPENDKIM_CASE=D OPENDKIM_TARGET=nolua
        if ! opendkim_neutralise_plan "$dir" "$map"
        then
            OPENDKIM_CASE=D-unsafe OPENDKIM_TARGET=quiet OPENDKIM_PLAN=()
            OPENDKIM_REASONS=("AUTH macros still reach opendkim after the planned changes:$OPENDKIM_UNSAFE")
        fi
        return 0
    fi
    if $all_authen
    then
        OPENDKIM_CASE=A OPENDKIM_TARGET=lua
        [[ ${OPENDKIM_PF_MAIN[milter_mail_macros]:-} == "$m" ]] && OPENDKIM_PLAN+=("pc"$'\t'"-X"$'\t'"milter_mail_macros")
        [[ ${OPENDKIM_PF_MAIN[smtpd_milter_maps]:-} == "$map" ]] && OPENDKIM_PLAN+=("pc"$'\t'"-X"$'\t'"smtpd_milter_maps")
    elif $b_ok && $w_owned && (( ${#wsvc[@]} == 0 ))
    then
        OPENDKIM_CASE=B OPENDKIM_TARGET=nolua
        OPENDKIM_REASONS=("${hide[@]}")
        [[ $(cat "$dir/srvctl-milter-map" 2> /dev/null) == "$(opendkim_map_text)" ]] || OPENDKIM_PLAN+=("map")
        [[ -v OPENDKIM_PF_MAIN[milter_mail_macros] ]] || OPENDKIM_PLAN+=("pc"$'\t'"-e"$'\t'"milter_mail_macros = $m")
        [[ -v OPENDKIM_PF_MAIN[smtpd_milter_maps] ]] || OPENDKIM_PLAN+=("pc"$'\t'"-e"$'\t'"smtpd_milter_maps = $map")
    elif $w_owned && (( ${#wsvc[@]} == 0 && ${#reach[@]} == 0 ))
    then
        OPENDKIM_CASE=C-isolate OPENDKIM_TARGET=local-only
        OPENDKIM_REASONS=("${hide[@]}")
        for s in "${OPENDKIM_PF_SIGMA[@]}"
        do
            [[ -v OPENDKIM_PF_SVC[$s/smtpd_milters] ]] && continue
            OPENDKIM_PLAN+=("pc"$'\t'"-P"$'\t'"$s/smtpd_milters=" "iso+"$'\t'"$s")
        done
        return 0
    else
        OPENDKIM_CASE=C-conflict OPENDKIM_TARGET=quiet
        OPENDKIM_REASONS=("${hide[@]}" "${wsvc[@]}" "${reach[@]}")
        return 0
    fi
    ## lua and nolua (B): srvctl's isolation overrides are not needed any more
    for s in "${OPENDKIM_ISO_KEEP[@]}"
    do
        OPENDKIM_PLAN+=("pc"$'\t'"-PX"$'\t'"$s/smtpd_milters" "iso-"$'\t'"$s")
    done
}

## opendkim_conf_key <file> <key> [value]: set one key (in place, case-
## insensitive match, duplicates dropped, appended when missing) or, without
## a value, delete it.
function opendkim_conf_key {
    local file="$1" key="$2" value="${3:-}" tmp
    tmp="$(mktemp)"
    awk -v k="$key" -v v="$value" '
        BEGIN { lk = tolower(k) }
        tolower($1) == lk { if (v != "" && !done) { print k "        " v; done = 1 }; next }
        { print }
        END { if (v != "" && !done) print k "        " v }' "$file" > "$tmp"
    cat "$tmp" > "$file"
    rm -f "$tmp"
}

## opendkim_conf_state <conf> quiet|lua|nolua|local-only: the signing keys of
## opendkim.conf for a target (lua also installs the policy script). Sets
## OPENDKIM_CONF_CHANGED.
function opendkim_conf_state {
    local conf="$1" target="$2" work key
    local policy="${SC_OPENDKIM_POLICY:-/etc/opendkim/srvctl-signing-policy.lua}"
    OPENDKIM_CONF_CHANGED=false
    work="$(mktemp)"
    cat "$conf" > "$work"
    ## each of these can make another client a signer or pick a key outside the tables
    for key in Domain KeyFile MacroList MTA SenderMacro
    do
        if awk -v k="$key" 'tolower($1) == tolower(k) { f = 1 } END { exit !f }' "$work"
        then
            opendkim_conf_key "$work" "$key"
            msg "opendkim: removed $key from $conf"
        fi
    done
    opendkim_conf_key "$work" InternalHosts /var/opendkim/InternalHosts
    case "$target" in
        lua)
            opendkim_conf_key "$work" SigningTable refile:/var/opendkim/EmptySigningTable
            opendkim_conf_key "$work" SetupPolicyScript "$policy"
            if ! cmp -s "$SC_INSTALL_DIR/modules/opendkim/conf/signing-policy.lua" "$policy"
            then
                mkdir -p "$(dirname "$policy")"
                install -m 0644 "$SC_INSTALL_DIR/modules/opendkim/conf/signing-policy.lua" "$policy"
                OPENDKIM_CONF_CHANGED=true
            fi
            ;;
        nolua|local-only)
            opendkim_conf_key "$work" SigningTable refile:/var/opendkim/HostSigningTable
            opendkim_conf_key "$work" SetupPolicyScript
            ;;
        *)
            opendkim_conf_key "$work" SigningTable refile:/var/opendkim/EmptySigningTable
            opendkim_conf_key "$work" SetupPolicyScript
            ;;
    esac
    if ! cmp -s "$work" "$conf"
    then
        cat "$work" > "$conf"
        OPENDKIM_CONF_CHANGED=true
    fi
    rm -f "$work"
}

function opendkim_conf_apply { # conf target
    opendkim_conf_state "$1" "$2"
    if $OPENDKIM_CONF_CHANGED
    then
        msg "opendkim: $1 set for '$2' signing"
        restart_opendkim
    fi
}

## opendkim_restart_postfix: a full restart, so no smtpd process keeps the old
## macro or milter settings. A postfix that is not running reads the new
## files when it starts.
function opendkim_restart_postfix {
    if ! systemctl is-active --quiet postfix.service
    then
        msg "opendkim: postfix is not running; it reads the new configuration when it starts"
        return 0
    fi
    systemctl restart postfix.service && systemctl is-active --quiet postfix.service
}

function opendkim_report {
    local r
    case "$OPENDKIM_CASE" in
        A) msg "opendkim: Lua signing policy: senders sign only the domains they are entitled to" ;;
        B)
            for r in "${OPENDKIM_REASONS[@]}"
            do
                err "opendkim: $r does not pass the SASL login: Lua signing refused, container and SMTP AUTH mail is not signed on $HOSTNAME (host-local mail is)"
            done
            ;;
        C-isolate)
            for r in "${OPENDKIM_REASONS[@]}"
            do
                err "opendkim: $r hides the SASL login: SMTP mail (containers, AUTH) is not signed or verified on $HOSTNAME until it is fixed; host-local mail is still signed"
            done
            ;;
        D) err "opendkim is built without Lua: container and SMTP AUTH mail is not signed on $HOSTNAME, only host-local mail is (decision 013)" ;;
        C-conflict)
            for r in "${OPENDKIM_REASONS[@]}"
            do
                err "opendkim: signing suspended on $HOSTNAME (H1): $r; fix it, then sc regenerate"
            done
            ;;
        *)
            for r in "${OPENDKIM_REASONS[@]}"
            do
                err "opendkim: signing suspended on $HOSTNAME: $r"
            done
            ;;
    esac
}

## regenerate_opendkim_conf [opendkim.conf] [postfix dir]
## Set the signing policy (see the block comment above); only targeted keys
## change. Whether postfix must restart is decided before any edit: a
## non-empty plan, or the pending marker of an earlier failed restart. Then:
## opendkim quiet -> marker -> postfix edits -> postfix restart -> marker
## removed -> opendkim target. A failure anywhere leaves opendkim quiet.
function regenerate_opendkim_conf {
    local conf="${1:-/etc/opendkim.conf}" dir="${2:-/etc/postfix}" pending
    pending="$dir/srvctl-postfix-restart-pending"
    if [[ ! -f $conf ]]
    then
        err "opendkim: $conf is missing; signing policy not set"
        return 0
    fi
    if [[ -f $dir/main.cf && -f $dir/master.cf ]]
    then
        opendkim_classify "$dir"
    else
        OPENDKIM_CASE=Z OPENDKIM_TARGET=quiet OPENDKIM_PLAN=()
        OPENDKIM_REASONS=("no postfix configuration in $dir")
    fi
    opendkim_report

    if [[ $OPENDKIM_TARGET == quiet ]]
    then
        opendkim_conf_apply "$conf" quiet
        return 0
    fi
    if (( ${#OPENDKIM_PLAN[@]} == 0 )) && [[ ! -e $pending ]]
    then
        opendkim_conf_apply "$conf" "$OPENDKIM_TARGET"
        return 0
    fi
    opendkim_conf_apply "$conf" quiet
    : > "$pending"
    if ! opendkim_plan_apply "$dir" live
    then
        err "opendkim: postfix changes failed: opendkim stays quiet (signs nothing)"
        return 0
    fi
    if ! opendkim_restart_postfix
    then
        err "opendkim: postfix restart failed: opendkim stays quiet (signs nothing) until a regenerate restarts postfix"
        return 0
    fi
    rm -f "$pending"
    opendkim_conf_apply "$conf" "$OPENDKIM_TARGET"
}
