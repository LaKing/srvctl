#!/bin/bash

##
##   modules/branding/libs/update-install-lib.sh — host error pages.
##
##   Sourced via load_libs whenever the module is enabled; used only by
##   hooks/update-install-host.sh during 'sc update-install'. For each
##   status code it writes two files under /var/www/html:
##     <code>.html — branded error page for web servers
##     <code>.http — the same page prefixed with a raw HTTP/1.1 response
##                   header block, served byte-verbatim by haproxy via
##                   'errorfile' (see modules/haproxy/haproxy.js)
##   The two heredoc bodies are duplicated on purpose and must stay
##   identical; the .http status line and header block are wire format —
##   do not reformat them.
##

## setup_varwwwhtml_error <code> <text>
function setup_varwwwhtml_error { ## type, text

    local _name _text _index_html _index_http _logo

    mkdir -p /var/www/html

    _name="$1"
    _text="$2"
    _index_html="/var/www/html/$_name.html"
    ## used in haproxy
    _index_http="/var/www/html/$_name.http"
    _logo="$(cat "$SC_INSTALL_DIR/modules/branding/logo.svg")"

cat > "$_index_html" << EOF
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

cat > "$_index_http" << EOF
HTTP/1.1 $_name $_text
Cache-Control: no-cache
Connection: close
Content-Type: text/html
Retry-After: 60

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
