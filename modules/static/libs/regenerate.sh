#!/bin/bash

function regenerate_static_server() {
    msg "regenerate static server index files"
    for dir in $(cfg cluster container_list)
    do
        mkdir -p "/var/srvctl3/storage/static/$dir/html"
        if [[ ! -f "/var/srvctl3/storage/static/$dir/html/index.html" ]]
        then
            setup_index_html "$dir (static)" "/var/srvctl3/storage/static/$dir/html"
        fi
    done
}
