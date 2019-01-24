#!/bin/node

/*srvctl */

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

function out(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

const CMD = process.argv[2];
// constatnts

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os = require("os");
const HOSTNAME = os.hostname();
const SC_COMPANY_DOMAIN = process.env.SC_COMPANY_DOMAIN;
const localhost = "localhost";
const br = "\n";
process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error("DATA-ERROR:", msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}

// variables
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = {};
//var user = '';
//var container = '';

var use_codepad = false;
if (process.env.SC_USE_CODEPAD === "true") use_codepad = true;

// create an array of arrays based on the dots
var aa = [];
Object.keys(datastore.containers).forEach(function(i) {
    if (i.split(".")[0] === "mail") return;
    var l = i.split(".").length;
    if (!aa[l]) aa[l] = [];
    aa[l].push(i);
});

// create the sorted version of the containers object
for (var j = aa.length - 1; j > 0; j--) {
    if (aa[j]) for (var k = 0; k < aa[j].length; k++) containers[aa[j][k]] = datastore.containers[aa[j][k]];
}

//containers = datastore.containers;

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions

function don(d) {
    return d.replace(/\./g, "-");
}

function ddn(d) {
    return d.replace(/\./g, "-") + "." + SC_COMPANY_DOMAIN;
}

// str += br + '';

function acl(p, h, n) {
    // proto host port
    var str = "";

    if (n === 80 || n === 443) {
        str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + h + " }";
        str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + ddn(h) + " }";
    }

    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + h + ":" + n + " }";
    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + ddn(h) + ":" + n + " }";

    return str;
}

function aacl(p, h, a, n) {
    // proto host altname port
    var str = "";

    if (n === 80 || n === 443) {
        str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + a + " }";
        str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + ddn(a) + " }";
    }

    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + a + ":" + n + " }";
    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + ddn(a) + ":" + n + " }";

    return str;
}

const rule_exeptions = " !.well-known-acl";

function get_well_known_acl() {
    var str = "";
    str += br + "    acl .well-known-acl path_beg /.well-known";
    str += br + "    acl letsencrypt-acl path_beg /.well-known/acme-challenge/";
    str += br + "    acl thunderbird-acl path_beg /.well-known/autoconfig/mail/";
    str += br + "    acl srvctl3data-acl path_beg /.well-known/srvctl/datastore/";
    return br + str;
}

function get_well_known() {
    var str = "";
    str += br + "    use_backend letsencrypt-backend if letsencrypt-acl" + br;
    str += br + "    use_backend thunderbird-backend if thunderbird-acl" + br;
    str += br + "    use_backend srvctl3data-backend if srvctl3data-acl" + br;
    return br + str;
}

function redirect(p, h, d) {
    // proto host dest
    var str = "";
    str += br + "    redirect prefix " + p + "://" + h + " code 301 if { hdr(host) -i " + d + " }" + rule_exeptions;
    if (d.substring(0, 4) !== "www.") str += br + "    redirect prefix " + p + "://" + h + " code 301 if { hdr(host) -i www." + d + " }" + rule_exeptions;
    return str;
}

function get_global() {
    var str = "";
    str += br + "global";
    str += br + "    daemon";
    str += br + "    maxconn 4096";
    str += br + "    log         127.0.0.1 local2";
    str += br + "    chroot      /var/lib/haproxy";
    str += br + "    pidfile     /var/run/haproxy.pid";
    str += br + "    user        haproxy";
    str += br + "    group       haproxy";
    str += br + "    stats socket /var/lib/haproxy/stats";
    str += br + "    ssl-default-bind-ciphers PROFILE=SYSTEM";
    str += br + "    ssl-default-server-ciphers PROFILE=SYSTEM";
    str += br + "    tune.ssl.default-dh-param 2048";
    str += br + "    ssl-server-verify none";
    str += br + "    stats socket /var/run/haproxy.stat";
    str += br;

    str += br + "defaults";
    str += br + "        mode                    http";
    str += br + "        log                     global";

    // ?
    str += br + "        option                  httplog";

    //str += br + '        option                  dontlognull';
    str += br + "        option http-server-close";
    //?
    str += br + "        option forwardfor       except 127.0.0.0/8";

    str += br + "        option                  redispatch";
    str += br + "        retries                 3";
    str += br + "        timeout http-request    10s";
    str += br + "        timeout queue           1m";
    str += br + "        timeout connect         1s";
    str += br + "        timeout client          1m";
    str += br + "        timeout server          3m"; /// 1m is the default!
    str += br + "        timeout http-keep-alive 10s";
    str += br + "        timeout check           10s";
    str += br + "        maxconn                 3000";

    str += br + "        option forwardfor";
    str += br + "        option http-server-close";

    //str += br + '       stats enable';
    //str += br + '       stats uri /stats';
    //str += br + '       stats realm Haproxy\\ Statistics';
    //str += br + '       stats auth stat:stat'; // we keep this no-password style password for now

    str += br + "        errorfile 400 /var/www/html/400.html";
    str += br + "        errorfile 403 /var/www/html/403.html";
    //https://serverfault.com/questions/885264/haproxy-error-400-bad-request-randomly?noredirect=1#comment1141829_885264
    //str += br + '        errorfile 408 /var/www/html/408.html';
    str += br + "        errorfile 500 /var/www/html/500.html";
    //  status code 501 not handled by 'errorfile', error customization will be ignored.
    //str += br + '        errorfile 501 /var/www/html/501.html';
    str += br + "        errorfile 502 /var/www/html/502.html";
    str += br + "        errorfile 503 /var/www/html/503.html";
    str += br + "        errorfile 504 /var/www/html/504.html";

    str += br + "        compression algo gzip";
    str += br + "        compression type text/html text/plain text/css";

    str += br + "";

    return str;
}

function get_frontend_http() {
    var str = "";
    str += br + "frontend http";
    str += br + "    bind *:80";
    str += br;

  	str += br + get_well_known_acl();
  
    // REDIRECT RULEs
    Object.keys(containers).forEach(function(i) {
        str += br + redirect("http", i, "www." + i);
        // handle aliases
        if (containers[i].aliases) {
            for (j = 0; j < containers[i].aliases.length; j++) {
                str += redirect("http", i, containers[i].aliases[j]);
            }
        }

        if (containers[i]["http-redirect"] !== undefined && containers[i]["http-redirect"] !== "none") {
            if (containers[i]["http-redirect"] === "https") str += br + "    redirect prefix https://" + i + " code 301 if { hdr(host) -i " + i + " }" + rule_exeptions;
            else str += br + "    redirect prefix " + containers[i]["http-redirect"] + " code 301 if { hdr(host) -i " + i + " }" + rule_exeptions;
        }
    });
    str += br;

    str += get_well_known();

    str += br;
    // USE BACKENDs
    Object.keys(containers).forEach(function(i) {
        // the standard container is started, use it, otherwise it will fallback to the default
        if (containers[i].static) msg("Using only static config for " + i);
        else str += acl("http", i, 80);

        if (containers[i].altnames) {
            for (j = 0; j < containers[i].altnames.length; j++) {
                str += aacl("http", i, containers[i].altnames[j], 80);
            }
        }
    });

    str += br + "    default_backend default";

    str += br;
    return str;
}

function get_frontend_https() {
    var str = "";

    str += br + "frontend https";
    str += br + "    bind *:443 ssl crt /var/haproxy";
    str += br;
  
  	str += br + get_well_known_acl();

    // REDIRECT
    Object.keys(containers).forEach(function(i) {
        str += br + redirect("https", i, "www." + i);
        // handle aliases
        if (containers[i].aliases) {
            for (j = 0; j < containers[i].aliases.length; j++) {
                str += redirect("https", i, containers[i].aliases[j]);
            }
        }

        if (containers[i]["https-redirect"] !== undefined && containers[i]["https-redirect"] !== "none") {
            if (containers[i]["https-redirect"] === "http") str += br + "    redirect prefix http://" + i + " code 301 if { hdr(host) -i " + i + " }";
            else str += br + "    redirect prefix " + containers[i]["https-redirect"] + " code 301 if { hdr(host) -i " + i + " }";
        }
    });
    str += br;
    str += get_well_known();
    str += br;

    // USE BACKEND
    Object.keys(containers).forEach(function(i) {
        // the standard container
        if (containers[i].static) msg("Using only static config for " + i);
        else str += acl("https", i, 443);

        if (containers[i].altnames) {
            for (j = 0; j < containers[i].altnames.length; j++) {
                str += aacl("https", i, containers[i].altnames[j], 443);
            }
        }
    });

    str += br + "    default_backend default";

    str += br;
    return str;
}

function get_frontend_port(n, ssl) {
    var str = "";
    str += br + "frontend port" + n;
    str += br + "    bind *:" + n;
    if (ssl) str += " ssl crt /var/haproxy";

    str += br;

    // USE BACKEND (no redirects)
    Object.keys(containers).forEach(function(i) {
        // srvctl-releated port permissions based on configurations
        if (use_codepad && containers[i].type !== "codepad") {
            if (n === 9000 || n === 9001) return;
        }

        str += acl("port" + n, i, n);
    });

    // certfiles are in:
    // /etc/srvctl/cert
    // /var/haproxy/cert

    str += br + "    default_backend default";

    str += br;
    return str;
}

function get_backends_for_http() {
    var str = "";
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += br + "backend http:" + i;
        str += br + "    server http:" + i + " " + i + ":" + datastore.container_http_port(c);
        str += br + "";
    });

    str += br + "backend letsencrypt-backend";
    str += br + "       server letsencrypt 127.0.0.1:1028" + br;
    str += br + "backend thunderbird-backend";
    str += br + "       server thunderbird 127.0.0.1:1029" + br;
    str += br + "backend srvctl3data-backend";
    str += br + "       server srvctl3data 127.0.0.1:1030" + br;

    return str;
}

//, datastore.container_https_port(c)

function get_backends_for_https() {
    var str = "";
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += br + "backend https:" + i;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';
        str += br + "    server https:" + i + " " + i + ":" + datastore.container_https_port(c) + " ssl";
        str += br + "";
    });
    return str;
}

function get_backends_for_port(n, ssl) {
    var str = "";
    Object.keys(containers).forEach(function(i) {
        // srvctl-releated port permissions based on configurations
        if (use_codepad && containers[i].type !== "codepad") {
            if (n === 9000 || n === 9001) return;
        }

        var c = containers[i];
        str += br + "backend port" + n + ":" + i;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';
        str += br + "    server port" + n + ":" + i + " " + i + ":" + n;
        if (ssl) str += " ssl";
        str += br + "";
    });
    return str;
}

var cfg = "";
cfg += get_global();
cfg += get_frontend_http();
cfg += get_frontend_https();

// TODO, implement as hook?
// codepad
if (use_codepad) {
    cfg += get_frontend_port(9000, true);
    cfg += get_frontend_port(9001, true);
}

// elasticsearch
cfg += get_frontend_port(9200, true);

cfg += get_frontend_port(8080, false);
cfg += get_frontend_port(8443, true);

cfg += get_backends_for_http();
cfg += get_backends_for_https();

// codepad
if (use_codepad) {
    cfg += get_backends_for_port(9000, true);
    cfg += get_backends_for_port(9001, true);
}

// elasticsearch
cfg += get_backends_for_port(9200, false);

cfg += get_backends_for_port(8080, false);
cfg += get_backends_for_port(8443, true);

cfg += br + "backend default";
cfg += br + "    server default-server localhost:1282";

cfg += br + "";

function write_haproxy_cfg() {
    fs.writeFile("/etc/haproxy/haproxy.cfg", cfg, function(err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("wrote haproxy conf");
    });
}

write_haproxy_cfg();

process.exitCode = 0;

exit();
