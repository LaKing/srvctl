#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');
var datastore = require('../datastore/lib.js');

const CMD = process.argv[2];
// constatnts


const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os =  require('os');
const HOSTNAME = os.hostname();
const localhost = 'localhost';
const br = '\n';
process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === '') process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
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
var containers = datastore.containers;
var user = '';
var container = '';


//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions

function don(d) {
    return d.replace(/\./g, "-");
}
function ddn(d) {
    return d.replace(/\./g, "-") + '.' + HOSTNAME;
}



/*

function http_url_service(URL, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    URL "' + URL + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '    End';
    x += br + 'End';

    x += br;
    return x;
}
function https_url_service(URL, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    URL "' + URL + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '        HTTPS';
    x += br + '    End';
    x += br + 'End';

    x += br;
    return x;
}
function http_head_service(host, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    headRequire "Host: ' + host + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '        TimeOut 300';
    x += br + '    End';
    
    if (process.env.SC_USE_STATIC) {
        x += br + '    Emergency';
        x += br + '        Address 127.0.0.1';
        x += br + '        Port 1280';
        x += br + '    End';
    }
    
    x += br + 'End';

    x += br;
    return x;
}

function https_head_service(host, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    headRequire "Host: ' + host + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '        TimeOut 300';
    x += br + '        HTTPS';
    x += br + '    End';
    
    if (process.env.SC_USE_STATIC) {
        x += br + '    Emergency';
        x += br + '        Address 127.0.0.1';
        x += br + '        Port 1280';
        x += br + '    End';
    }
    
    x += br + 'End';

    x += br;
    return x;
}


function scan_path_for_cert(path) {
    var x = '';
    var dirs = fs.readdirSync(path);
    dirs.forEach(dir => {
        if (fs.existsSync(path + '/' + dir + '/cert.pem')) {
            x += 'Cert "' + path + '/' + dir + '/cert.pem"' + br;
        }
    });
    return x;
}

function write_var_haproxy_http_cfg() {
    var str = '';
    
    str += http_url_service("^/.well-known/acme-challenge/*", localhost, 1028);
    str += http_url_service("^/.well-known/autoconfig/mail/config-v1.1.xml", localhost, 1029);

    // normal service
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += http_head_service(i, i, datastore.container_http_port(c));
    });
    // direct acces domain
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += http_head_service(ddn(i), i, datastore.container_http_port(c));
    });
    if (process.env.SC_USE_STATIC)
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += http_head_service('static.' + i, '127.0.0.1', '1280');
    });
    fs.writeFile('/var/haproxy/http.cfg', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] haproxy srvctl http conf');
    });
}

function write_var_haproxy_cert_cfg() {
    var certs_includes = '';
    // certificates
    certs_includes += scan_path_for_cert('/etc/srvctl/cert');
    certs_includes += scan_path_for_cert('/var/haproxy/cert');
    fs.writeFile('/var/haproxy/cert.cfg', certs_includes, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] haproxy srvctl cert conf');
    });
}

function write_var_haproxy_https_cfg() {
    var str = '';
    // normal service
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += https_head_service(i, i, datastore.container_https_port(c));
    });
    // direct acces domain
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += https_head_service(ddn(i), i, datastore.container_https_port(c));
    });
    if (process.env.SC_USE_STATIC)
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += http_head_service('static.' + i, '127.0.0.1', '1281');
    });
    
    fs.writeFile('/var/haproxy/https.cfg', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] haproxy srvctl https conf');
    });
}


write_var_haproxy_http_cfg();
write_var_haproxy_cert_cfg();
write_var_haproxy_https_cfg();

*/

// str += br + '';

function acl(p, h) {
    var str = '';
    str += br + '    acl ' + p + ':' + h + ' hdr(host) -i ' + h;
    str += br + '    use_backend ' + p + ':' + h + ' if ' + p + ':' + h;
    return str;
}

function get_global() {
    var str = '';
    str += br + 'global';
    str += br + '    daemon';
    str += br + '    maxconn 4096';
    str += br + '    log         127.0.0.1 local2';
    str += br + '    chroot      /var/lib/haproxy';
    str += br + '    pidfile     /var/run/haproxy.pid';
    str += br + '    user        haproxy';
    str += br + '    group       haproxy';
    str += br + '    stats socket /var/lib/haproxy/stats';
    str += br + '    ssl-default-bind-ciphers PROFILE=SYSTEM';
    str += br + '    ssl-default-server-ciphers PROFILE=SYSTEM';
    str += br + '    tune.ssl.default-dh-param 2048';
    str += br + '    ssl-server-verify none';
    str += br;
    
    str += br + 'defaults';
    str += br + '        mode                    http';
    str += br + '        log                     global';
    //str += br + '        option                  httplog';
    str += br + '        option                  dontlognull';
    str += br + '        option http-server-close';
    //str += br + '        option forwardfor       except 127.0.0.0/8';
    str += br + '        option                  redispatch';
    str += br + '        retries                 3';
    str += br + '        timeout http-request    1s';
    str += br + '        timeout queue           1m';
    str += br + '        timeout connect         1s';
    str += br + '        timeout client          1m';
    str += br + '        timeout server          1m';
    str += br + '        timeout http-keep-alive 10s';
    str += br + '        timeout check           10s';
    str += br + '        maxconn                 3000';
    
    str += br + '        option forwardfor';
    str += br + '        option http-server-close';
    
    str += br + '       stats enable';
    str += br + '       stats uri /stats';
    str += br + '       stats realm Haproxy\\ Statistics';
    str += br + '       stats auth stat:stat'; // we keep this no-password style password for now
   
    //str += br + '        errorfile 400 /var/www/html/400.html';
    //str += br + '        errorfile 403 /var/www/html/400.html';
    //str += br + '        errorfile 408 /var/www/html/400.html';
    //str += br + '        errorfile 500 /var/www/html/500.html';
    //str += br + '        errorfile 502 /var/www/html/501.html';
    //str += br + '        errorfile 502 /var/www/html/500.html';
    //str += br + '        errorfile 503 /var/www/html/503.html';
    //str += br + '        errorfile 504 /var/www/html/500.html';
    
    str += br + '';  
    
    return str;
}

function get_frontend_http() {
    var str = '';
    str += br + 'frontend http';
    str += br + '    bind *:80';
       
    Object.keys(containers).forEach(function(i) {
        str += acl('http',i);
    });
    
    str += br + '    default_backend static';

    str += br;
    return str;
}

function get_frontend_https() {
    var str = '';
    str += br + 'frontend https';
    str += br + '    bind *:443 ssl crt /var/haproxy';
    str += br;
    
    Object.keys(containers).forEach(function(i) {
        str += acl('https',i);
    });
    // certfiles are in:
    // /etc/srvctl/cert
    // /var/haproxy/cert
    str += br + '    default_backend static';

    str += br;
    return str;
}

function get_backends_for_http() {
    var str = '';
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += br + 'backend http:' + i;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';
        str += br + '    server http:' + i + ' ' + i + ':' + datastore.container_http_port(c);
        str += br + '';
    });
    return str;
}

//, datastore.container_https_port(c)

function get_backends_for_https() {
    var str = '';
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        str += br + 'backend https:' + i;
        // for https only
        //str += br + '    redirect scheme https if !{ ssl_fc }';
        str += br + '    server https:' + i + ' ' + i + ':' + datastore.container_https_port(c) + ' ssl';
        str += br + '';
    });
    return str;
}

var cfg = '';
cfg += get_global();
cfg += get_frontend_http();
cfg += get_frontend_https();

cfg += get_backends_for_http();
cfg += get_backends_for_https();

cfg += br + 'backend static';
cfg += br + '    server static-server localhost:1280'; 
cfg += br + '';

function write_haproxy_cfg() {
    fs.writeFile('/etc/haproxy/haproxy.cfg', cfg, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] haproxy conf');
    });
}

write_haproxy_cfg();

process.exitCode = 0;

exit();
