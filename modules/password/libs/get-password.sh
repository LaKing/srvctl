#!/bin/bash

## password/libs/get-password.sh - sourced into every srvctl shell by
## load_libs. get_password: echoes one pronounceable random password of
## the form Word-Word (e.g. Kelto-Ardu), 11-15 chars, charset [A-Za-z-].
## Same alphabets and pattern as lib.js (bash ad == JS ad.concat(ar)).

function get_password {

    local aa ad ar bb bc adl aal arl bbl bcl ra0 ra1 p

    ## alphabets: ad = consonants/clusters, aa/ar = upper/lowercase
    ## consonants, bb/bc = lower/uppercase vowels
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

    ## FIXME(v4): $RANDOM is not cryptographically secure and the pattern
    ## entropy is ~39 bits, yet these passwords end up as long-lived
    ## DB/user credentials (mariadb, wordpress); use a CSPRNG in v4.
    ra0=$(( RANDOM % 2 ))
    ra1=$(( RANDOM % 2 ))
    
    p=''

    ## word 1: uppercase-vowel + consonant, or consonant + vowel + consonant
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

    ## word 2: same shape as word 1
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
    
    ## return password
    echo "$p"
}
