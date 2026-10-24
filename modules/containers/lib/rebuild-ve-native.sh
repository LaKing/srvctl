#!/bin/bash

## Runs INSIDE the new container after rebuild-ve-restore.sh, as its root:
## 'ssh VE bash -s < this', from rebuild_ve_restore (libs/rebuildlib.sh).
##
## Native Node modules in the local units' trees that are bound to one Node ABI
## (NAN, no N-API import: canvas 2.x, @serialport/bindings 9, alsa) were built
## for the old node and stop the app on the new one (seen on r2: carco.hu,
## canvas 2.11.2 loaded by jsdom 20). Each is rebuilt here with node-gyp against
## the installed node. N-API modules (canvas 3.x) work as they are.
##
## A module that does not build keeps its old binary (build.before-rebuild is
## put back) and is reported: the check then shows whether the app loads it.
## nan before 2.19 does not compile for Node 22: a current one replaces it for
## the build only. Needs the network (dnf, npm).

set -u
B=/srv/backup
units="$(sed -n 's/^localunits=//p' "$B/manifest")"
[[ -n $units ]] || exit 0

mapfile -t mods < <(
    grep '^/srv/' "$B/paths" | while read -r p
    do
        find "$p" -path '*/build/Release/*.node' -not -path '*/obj.target/*' 2> /dev/null
    done | while read -r f
    do
        nm -D "$f" 2> /dev/null | grep -q ' U napi_' || echo "${f%/build/Release/*}"
    done | sort -u
)
((${#mods[@]})) || exit 0

## build tools; the headers of exactly the installed node (nodejs22-bin -> nodejs22-devel)
nodepkg="$(rpm -qf --qf '%{NAME}' /usr/bin/node)"
deps=(gcc-c++ make python3 "${nodepkg%-bin}-devel")
for m in "${mods[@]}"
do
    case "${m##*/}" in
        canvas) deps+=(cairo-devel pango-devel libjpeg-turbo-devel giflib-devel librsvg2-devel) ;;
        alsa) deps+=(alsa-lib-devel) ;;
    esac
done
dnf -y -q install "${deps[@]}" || echo "== NOTE: some build dependencies did not install"

nan="$(mktemp -d)"
(cd "$nan" && npm pack -q nan@2.22 > /dev/null && tar xzf nan-*.tgz) || echo "== NOTE: no current nan, builds use the installed one"

for m in "${mods[@]}"
do
    echo "== native module ${m#/srv/}"
    nd="$(cd "$m" && node -p 'require("path").dirname(require.resolve("nan/package.json"))' 2> /dev/null)"
    old=false
    if [[ -n $nd && -d $nan/package ]] && node -e "process.exit(Number(require('$nd/package.json').version.split('.')[1] >= 19))"
    then
        mv "$nd" "$nd.before-rebuild" && cp -a "$nan/package" "$nd" && old=true
    fi
    rm -rf "$m/build.before-rebuild"
    mv "$m/build" "$m/build.before-rebuild"
    ## built, and every binary the old build had loads: the ones the app loads. Not every new
    ## .node: canvas 2.x also builds canvas-postbuild.node, a helper target that never
    ## self-registers (seen on r2: digby.hu). A subshell: the loop's exit must not end the script.
    if (cd "$m" && npx --yes node-gyp@11 rebuild --nodedir=/usr > "$m/build.log" 2>&1) && (for f in "$m"/build.before-rebuild/Release/*.node; do node -e "require('$m/build/Release/${f##*/}')" || exit 1; done)
    then
        chown -R --reference="$m" "$m/build"
        echo "== rebuilt for node $(node --version), the old build is in build.before-rebuild"
    else
        tail -n 5 "$m/build.log"
        rm -rf "$m/build" && mv "$m/build.before-rebuild" "$m/build"
        echo "== NOTE: ${m#/srv/} did not build for node $(node --version); the old binary stays (log: $m/build.log)"
    fi
    $old && rm -rf "$nd" && mv "$nd.before-rebuild" "$nd"
done
rm -rf "$nan"

# shellcheck disable=SC2086 # a space-separated list of unit names
systemctl restart $units
