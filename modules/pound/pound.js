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


function ddn(d) {
    return d.replace(/\./g, "-") + '.' + HOSTNAME;
}

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

function write_var_pound_http_cfg() {
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
    fs.writeFile('/var/pound/http.cfg', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] pound srvctl http conf');
    });
}

function write_var_pound_cert_cfg() {
    var certs_includes = '';
    // certificates
    certs_includes += scan_path_for_cert('/etc/srvctl/cert');
    certs_includes += scan_path_for_cert('/var/pound/cert');
    fs.writeFile('/var/pound/cert.cfg', certs_includes, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] pound srvctl cert conf');
    });
}

function write_var_pound_https_cfg() {
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
    
    fs.writeFile('/var/pound/https.cfg', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] pound srvctl https conf');
    });
}


write_var_pound_http_cfg();
write_var_pound_cert_cfg();
write_var_pound_https_cfg();
process.exitCode = 0;

exit();
