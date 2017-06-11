#!/bin/bash

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