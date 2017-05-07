#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');

const CMD = process.argv[2];
// constatnts

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';

const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/users.json';
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';


const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const HOSTNAME = process.env.HOSTNAME;
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
var hosts = {};
var users = {};
var resellers = {};
var containers = {};
var user = '';
var container = '';


//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions
function load_hosts() {
    try {
        hosts = JSON.parse(fs.readFileSync(SC_HOSTS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
    }
}
// data functions
function load_resellers() {
    resellers = {};
    resellers.root = users.root;
    resellers.root.is_reseller_id = 0;
    Object.keys(users).forEach(function(i) {
        if (users[i].is_reseller_id !== undefined)
            resellers[i] = users[i];
    });
}

function load_users() {
    try {
        users = JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
        if (users.root === undefined) {
            users.root = {};
            users.root.id = 0;
            users.root.uid = 0;
            users.root.reseller = 'root';
            users.root.is_reseller_id = 0;
        }
        // resellers are also users
        load_resellers();

    } catch (err) {
        return_error('READFILE ' + SC_USERS_DATA_FILE + ' ' + err);
    }
}

function load_containers() {
    try {
        containers = JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
    }
}

function ddn(d) {
    return d.replace(/\./g, "-") + '.' + HOSTNAME;
}

function container_http_port(container) {
    if (container.http_port) return container.http_port;
    else return 80;
}

function container_https_port(container) {
    if (container.https_port) return container.https_port;
    else return 443;
}

function _url_service(URL, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    URL "' + URL + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '    End';
    x += br + 'End';

    x += br;
    out(x);
}

function _head_service(host, Address, Port) {
    var x = '';

    x += br + 'Service';
    x += br + '    headRequire "Host: ' + host + '"';
    x += br + '    BackEnd';
    x += br + '        Address ' + Address;
    x += br + '        Port ' + Port;
    x += br + '    End';
    x += br + 'End';

    x += br;
    out(x);
}

function scan_path_for_cert(path) {
    var dirs = fs.readdirSync(path);
    dirs.forEach(dir => {
        if (fs.existsSync(path + '/' + dir + '/cert.pem')) {
            out('Cert "' + path + '/' + dir + '/cert.pem"');
        }
    });
}

load_hosts();
load_containers();
load_users();

if (CMD === 'http') {

    _url_service("^/.well-known/acme-challenge/*", localhost, 1028);
    _url_service("^/.well-known/autoconfig/mail/config-v1.1.xml", localhost, 1029);

    // normal service
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        _head_service(i, i, container_http_port(c));
    });
    // direct acces domain
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        _head_service(ddn(i), i, container_http_port(c));
    });

}

if (CMD === 'cert') {

    // certificates
    scan_path_for_cert('/etc/srvctl/cert');
    scan_path_for_cert('/var/pound/cert');
}

if (CMD === 'https') {
    // normal service
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        _head_service(i, i, container_https_port(c));
    });
    // direct acces domain
    Object.keys(containers).forEach(function(i) {
        var c = containers[i];
        _head_service(ddn(i), i, container_https_port(c));
    });

}

exit();