#!/bin/bash

function get_disk_usage {
    du -hs /srv/$1 | head -c 4
}
