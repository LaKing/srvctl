#!/bin/bash

function setup_varwwwhtml_error { ## type, text
    
    local _name _text _index _logo
    
    mkdir -p /var/www/html
    
    _name="$1"
    # shellcheck disable=SC2034
    _text="$2"
    _index="/var/www/html/$_name.html"
    _logo="$(cat "$SC_INSTALL_DIR/modules/branding/logo.svg")"
    
    
cat > "$_index" << EOF
<!DOCTYPE html>
<html lang="en">
  <head>
    <meta charset="utf-8">
    <title>ERROR $_name</title>
    <style type="text/css"> html, body {overflow: hidden;} </style>
  </head>
<body style="background-color:#333;">
    <div id="header" style="background-color:#222;">
        <p align="center">
            $_logo
        </p>
    </div>
        <p align="center">
                <font style="margin-left: auto; margin-right: auto; color: #FFF" size="6px" face="Arial">
                Error $_name @ $HOSTNAME<br>
                $_text
                <br><br></font>
                <font style="margin-left: auto; margin-right: auto; color: #555" size="5px" face="Arial">
                ERROR!<br>HIBA!<br>FEHLER!<br>ERREUR!<br>POGREŠKA!<br>ERRORE!<br>FEJL!<br>FOUT!<br>NAPAKA!<br>HATA!<br>
                ERRO!<br>BŁĄD!<br>CHYBA!<br>ПОМИЛКА!<br>EROARE!<br>エラー!<br>VILLA!<br>FEL!<br>LỖI!<br>GRESKA!<br>
                ОШИБКА!<br>错误<br>ข้อผิดพลาด!<br>त्रुटि!<br>កំហុស!<br>ΛΆΘΟΣ!<br>දෝෂය !<br>ХАТО!<br>VIRHE!<br>Kikowaena!<br>IPHUTHA!
            </font>
        </p>
</body>
</html>
EOF
    
}
