#!/bin/bash

## functions common to all areas of srvctl

function load_libs {
    
    for sourcefile in $SC_INSTALL_DIR/libs/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
}

function load_commands {
    
    for sourcefile in $SC_INSTALL_DIR/commands/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
    
    if [ -d /root/srvctl-includes ] && [ ! -z "$(ls /root/srvctl-includes)" ]
    then
        for sourcefile in /root/srvctl-includes/*
        do
            [[ -f "$sourcefile" ]] && source "$sourcefile"
        done
    fi
    
}
function hint_commands {
    for sourcefile in $SC_INSTALL_DIR/commands/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
    
    if [ -d /root/srvctl-includes ] && [ ! -z "$(ls /root/srvctl-includes)" ]
    then
        for sourcefile in /root/srvctl-includes/*
        do
            [[ -f "$sourcefile" ]] && source "$sourcefile"
        done
    fi
}

function load_cms {
    for sourcefile in $SC_INSTALL_DIR/ve-cms/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
}

function hint_cms {
    for sourcefile in $SC_INSTALL_DIR/ve-cms/*
    do
        [[ -f "$sourcefile" ]] && source "$sourcefile"
    done
}

