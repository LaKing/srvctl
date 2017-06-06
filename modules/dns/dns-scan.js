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
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var user = '';
var container = '';

const dns = require('dns');

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions

function scan_domain(domain) {
    
    if (containers[domain].dns_scan === undefined) containers[domain].dns_scan = {};
    var cdds = containers[domain].dns_scan;
    cdds.A={};
    dns.resolve4(domain, function(err, addresses) {
        if (err) return console.log(err.code, err.hostname);
            if (addresses !== undefined)
            addresses.forEach((a) => {
                dns.reverse(a, (err, hostnames) => {
                if (err) return console.log(err.code, err.hostname);
                console.log(domain, 'IN A',hostnames[0], '(', a, ')');
                    cdds.A[a] = hostnames[0];
                });
            });
    });
    cdds.AAAA={};
    dns.resolve6(domain, function(err, addresses) {
        if (err) return console.log(err.code, err.hostname);
            if (addresses !== undefined)
            addresses.forEach((a) => {
                dns.reverse(a, (err, hostnames) => {
                if (err) return console.log(err.code, err.hostname);
                console.log(domain, 'AAAA',hostnames[0], '(', a, ')');
                    cdds.AAAA[a] = hostnames[0];
                });
            });
    });
    cdds.MX='';
    dns.resolveMx(domain, function(err, addresses) {
        if (err) return console.log(err.code, err.hostname);
         if (addresses !== undefined)
            addresses.forEach((a) => {
                if (err) return console.log(err.code, err.hostname);
                console.log(domain, 'MX',a.priority, a.exchange);
                cdds.MX[a.priority] = a.exchange;
            });
    });
    cdds.NS=[];
    dns.resolveNs(domain, function(err, addresses) {
        if (err) return console.log(err.code, err.hostname);
            if (addresses !== undefined) {
                 cdds.NS = addresses; 
                    addresses.forEach((a) => {
                    if (err) return console.log(err.code, err.hostname);
                    console.log(domain, 'NS', a);
                 });
            }
    });
}

function scan() {
    Object.keys(containers).forEach(function(i) {
        scan_domain(i);
    });
}

scan();

process.exitCode = 0;

process.on('exit', function (){
  fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
});

exit();
