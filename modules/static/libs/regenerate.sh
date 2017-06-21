#!/bin/bash

function regenerate_static_server() {
    msg "start"
    for dir in $(cfg system container_list)
    do
        msg "$dir"
        mkdir -p "/var/srvctl3/storage/static/$dir/html"
        if [[ ! -f "/var/srvctl3/storage/static/$dir/html/index.html" ]]
        then
            setup_index_html "$dir (static)" "/var/srvctl3/storage/static/$dir/html"
        fi
    done
}
