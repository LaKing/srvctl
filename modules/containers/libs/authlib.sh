#!/bin/bash

function authorize {
    
    if ! $SC_ROOT
    then
        ## authorize SC_USER
        
        ## ...
        dbg auth
    fi
}

function argument {
    if [[ -z $ARG ]]
    then
        err "No $1 given in argument."
        exit
    fi
}
