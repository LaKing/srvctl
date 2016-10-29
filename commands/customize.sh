#!/bin/bash

## @@@ customize COMMAND
## @en Create/edit a custom command.
## &en It is possible to create a custom command in ~/srvctl-includes
## &en A custom command should have a name, and will contain a blank help:

if [ -z "$ARG" ]
then
    err "Please give your command a name."
    exit 23
fi

mkdir -p "$SC_HOME/srvctl-includes"

local arg file
arg="${ARG,,}"
file="$SC_HOME/srvctl-includes/$arg.sh"

if [ -f "$file" ]
then
    mkdir -p "$SC_HOME/.srvctl/srvctl-includes.bak"
    cat "$file" > "$SC_HOME/.srvctl/srvctl-includes.bak/$arg-$NOW.sh"
fi

if [ ! -f "$file" ]
then
    
    if [ -f "$SC_INSTALL_DIR/commands/$arg.sh" ]
    then
        cat "$SC_INSTALL_DIR/commands/$arg.sh" > "$file"
        msg "$arg is a copy from srvctl"
    else
        
cat > "$file" << EOF
#!/bin/bash

## @@@ $ARG
## @en A Custom command from $SC_USER $NOW
## &en This command does something custom, like running a bash script.
## &en It might be customized further, depending on the author.

## Place your code here ...

EOF
        
        msg "Empty $arg created."
    fi
fi

run mcedit "$file"

[ -f "$file" ] || return

[ -f /bin/python ] && /bin/python "$SC_INSTALL_DIR/apps/beautify_bash.py" "$file"
[ -f /usr/bin/shellcheck ] && shellcheck "$file"

msg "$CMD done .."
