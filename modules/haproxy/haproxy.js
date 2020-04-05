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
Object.keys(datastore.containers).forEach(function(c) {
    if (c.split(".")[0] === "mail") return;
    var l = c.split(".").length;
    if (!aa[l]) aa[l] = [];
    aa[l].push(c);
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
        //str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + h + "." + HOSTNAME + " }";
    }

    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + h + ":" + n + " }";
    str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + ddn(h) + ":" + n + " }";
    //str += br + "    use_backend " + p + ":" + h + " if { hdr(host) -i " + h + "." + HOSTNAME + ":" + n + " }";

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
    str += br + "    acl pki-validations-acl path_beg /.well-known/pki-validation/";

    return br + str;
}

function get_well_known() {
    var str = "";
    str += br + "    use_backend letsencrypt-backend if letsencrypt-acl" + br;
    str += br + "    use_backend thunderbird-backend if thunderbird-acl" + br;
    str += br + "    use_backend srvctl3data-backend if srvctl3data-acl" + br;
    str += br + "    use_backend srvctl3data-backend if pki-validations-acl" + br;

    //str += br + "    use_backend srvctl3gui-backend if srvctl3gui-acl" + br;

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
    str += br + "        timeout connect         10s";
    str += br + "        timeout client          5m"; // 1m is the default!
    str += br + "        timeout server          5m"; // 1m is the default!
    str += br + "        timeout http-keep-alive 10s";
    str += br + "        timeout check           10s";
    str += br + "        maxconn                 50000"; // 3000 was a default

    str += br + "        option forwardfor";
    str += br + "        option http-server-close";

    //str += br + '       stats enable';
    //str += br + '       stats uri /stats';
    //str += br + '       stats realm Haproxy\\ Statistics';
    //str += br + '       stats auth stat:stat'; // we keep this no-password style password for now

    if (fs.existsSync("/var/www/html/400.http")) str += br + "        errorfile 400 /var/www/html/400.http";
    if (fs.existsSync("/var/www/html/403.http")) str += br + "        errorfile 403 /var/www/html/403.http";

    //https://serverfault.com/questions/885264/haproxy-error-400-bad-request-randomly?noredirect=1#comment1141829_885264
    //str += br + '        errorfile 408 /var/www/html/408.html';

    if (fs.existsSync("/var/www/html/500.http")) str += br + "        errorfile 500 /var/www/html/500.http";

    //  status code 501 not handled by 'errorfile', error customization will be ignored.
    //str += br + '        errorfile 501 /var/www/html/501.html';

    if (fs.existsSync("/var/www/html/502.http")) str += br + "        errorfile 502 /var/www/html/502.http";
    if (fs.existsSync("/var/www/html/503.http")) str += br + "        errorfile 503 /var/www/html/503.http";
    if (fs.existsSync("/var/www/html/504.http")) str += br + "        errorfile 504 /var/www/html/504.http";

    str += br + "        compression algo gzip";
    str += br + "    compression type text/css text/html text/javascript application/javascript text/plain text/xml application/json";

    str += br + "";

    return str;
}

// TODO if there is no http add a redirect to https

function get_frontend_http() {
    var str = "";
    str += br + "frontend http";
    str += br + "    bind *:80";
    str += br;

    str += br + get_well_known_acl();

    // REDIRECT RULEs
    Object.keys(containers).forEach(function(c) {
        str += br + redirect("http", c, "www." + c);
        // handle aliases
        if (containers[c].aliases) {
            for (j = 0; j < containers[c].aliases.length; j++) {
                str += redirect("http", c, containers[c].aliases[j]);
            }
        }

        // since 3.2.0.9 - as of 2019 July, we will use https by default
        // so unless http redirect is non, redirect to https.
        if (containers[c]["http-redirect"] === undefined) str += br + "    redirect prefix https://" + c + " code 301 if { hdr(host) -i " + c + " }" + rule_exeptions;

        if (containers[c]["http-redirect"] !== undefined && containers[c]["http-redirect"] !== "none") {
            if (containers[c]["http-redirect"] === "https") str += br + "    redirect prefix https://" + c + " code 301 if { hdr(host) -i " + c + " }" + rule_exeptions;
            else str += br + "    redirect prefix " + containers[c]["http-redirect"] + " code 301 if { hdr(host) -i " + c + " }" + rule_exeptions;
        }
    });
    str += br;

    str += get_well_known();

    str += br;
    // USE BACKENDs
    Object.keys(containers).forEach(function(c) {
        // the standard container is started, use it, otherwise it will fallback to the default
        if (containers[c].static) msg("Using only static config for " + c);
        else str += acl("http", c, 80);

        if (containers[c].altnames) {
            for (j = 0; j < containers[c].altnames.length; j++) {
                str += aacl("http", c, containers[c].altnames[j], 80);
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
    Object.keys(containers).forEach(function(c) {
        str += br + redirect("https", c, "www." + c);
        // handle aliases
        if (containers[c].aliases) {
            for (j = 0; j < containers[c].aliases.length; j++) {
                str += redirect("https", c, containers[c].aliases[j]);
            }
        }

        if (containers[c]["https-redirect"] !== undefined && containers[c]["https-redirect"] !== "none") {
            if (containers[c]["https-redirect"] === "http") str += br + "    redirect prefix http://" + c + " code 301 if { hdr(host) -i " + c + " }";
            else str += br + "    redirect prefix " + containers[c]["https-redirect"] + " code 301 if { hdr(host) -i " + c + " }";
        }
    });
    str += br;
    str += get_well_known();
    str += br;

    // USE BACKEND
    Object.keys(containers).forEach(function(c) {
        // the standard container
        if (containers[c].static) msg("Using only static config for " + c);
        else str += acl("https", c, 443);

        if (containers[c].altnames) {
            for (j = 0; j < containers[c].altnames.length; j++) {
                str += aacl("https", c, containers[c].altnames[j], 443);
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
    Object.keys(containers).forEach(function(c) {
        // srvctl-releated port permissions based on configurations
        if (use_codepad && containers[c].type !== "codepad") {
            if (n === 9000 || n === 9001) return;
        }

        str += acl("port" + n, c, n);
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
    Object.keys(containers).forEach(function(c) {
        str += br + "backend http:" + c;
        str += br + "    server http:" + c + " " + c + ":" + datastore.container_http_port(c);
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
    Object.keys(containers).forEach(function(c) {
        str += br + "backend https:" + c;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';

        str += br + "    server https:" + c + " " + c + ":" + datastore.container_https_port(c) + " ssl";
        str += br + "";
    });

    //str += br + "backend srvctl3gui-backend";
    //str += br + "       server srvctl3gui 127.0.0.1:250" + br;

    return str;
}

function get_backends_for_port(n, ssl) {
    var str = "";
    Object.keys(containers).forEach(function(c) {
        // srvctl-releated port permissions based on configurations
        if (use_codepad && containers[c].type !== "codepad") {
            if (n === 9000 || n === 9001) return;
        }

        str += br + "backend port" + n + ":" + c;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';
        str += br + "    server port" + n + ":" + c + " " + c + ":" + n;
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

// 1282 ?
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
