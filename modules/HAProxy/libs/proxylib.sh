#!/bin/bash

function regenerate_haproxy_conf {
    
    echo "HAproxy implementation not ready yet."
    
    # cat > /etc/haproxy/haproxy.cfg << EOF
    #
    #    frontend localhost
    #    mode http
    #    use_backend web1 if { hdr(host) -i abc.com }
    #    use_backend web1 if { hdr(host) -i def.com }
    #    use_backend web2 if { hdr(host) -i cba.com }
    #    use_backend web2 if { hdr(host) -i fed.com }
    #
    # backend web1
    #    server web1 web1.foo.com
    #
    # backend web2
    #    server web2 web2.foo.com
    #
    # EOF
    
}
