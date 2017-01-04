#!/bin/bash

function root_only {
    if $SC_ROOT
    then
        return 0
    else
        err "Authorization failure"
        exit 44
    fi
}

function sudomize {
    if ! $SC_ROOT
    then
        if ! sudo "$*"
        then
            err "Could not use sudo."
        fi
        exit
    fi
}


function get_password {
    
    local aa ad ar bb bc ra0 ra1 p
    
    declare -a ad=("ld" "ng" "nt" "lf" "br" "kr" "pr" "fr" "gr" "tr" "rt" "st" "b" "c" "d" "f" "g" "h" "j" "k" "l" "m" "n" "p" "r" "s" "t" "v" "z" "x" "q" "w")
    declare -a aa=("B" "C" "D" "F" "G" "H" "J" "K" "L" "M" "N" "P" "R" "S" "T" "V" "Z")
    declare -a ar=("b" "c" "d" "f" "g" "h" "j" "k" "l" "m" "n" "p" "r" "s" "t" "v" "z")
    declare -a bb=("a" "e" "i" "o" "u")
    declare -a bc=("A" "E" "I" "O" "U")
    
    adl=${#ad[@]}
    aal=${#aa[@]}
    arl=${#ar[@]}
    bbl=${#bb[@]}
    bcl=${#bc[@]}
    
    ra0=$(( RANDOM % 2 ))
    ra1=$(( RANDOM % 2 ))
    
    p=''
    
    if [[ $ra0 == 0 ]]
    then
        p=$p${bc[$(( RANDOM % bcl ))]}
        p=$p${ad[$(( RANDOM % adl ))]}
    else
        p=$p${aa[$(( RANDOM % aal ))]}
        p=$p${bb[$(( RANDOM % bbl ))]}
        p=$p${ar[$(( RANDOM % arl ))]}
    fi
    
    p=$p${bb[$(( RANDOM % bbl ))]}
    p=$p${ad[$(( RANDOM % adl ))]}
    p=$p${bb[$(( RANDOM % bbl ))]}
    
    p="$p-"
    
    if [[ $ra1 == 0 ]]
    then
        p=$p${bc[$(( RANDOM % bcl ))]}
        p=$p${ad[$(( RANDOM % adl ))]}
    else
        p=$p${aa[$(( RANDOM % aal ))]}
        p=$p${bb[$(( RANDOM % bbl ))]}
        p=$p${ar[$(( RANDOM % arl ))]}
    fi
    
    p=$p${bb[$(( RANDOM % bbl ))]}
    p=$p${ad[$(( RANDOM % adl ))]}
    p=$p${bb[$(( RANDOM % bbl ))]}
    
    ## return passowrd
    echo "$p"
}

function argument {
    if [[ -z $ARG ]]
    then
        err "Argument $1 missing."
        exit 32
    fi
}

function authorize {
    if $SC_ROOT
    then
        return
    else
        err "Authorization implementation not complete"
        exit 33
    fi
}
