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

const dns = require('dns');

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions

function scan_domain(domain) {
    
    if (containers[domain].dns_scan === undefined) containers[domain].dns_scan = {};

    containers[domain].dns_scan.A=[];
    dns.resolve4(domain, function(err, addresses) {
        //if (err) return console.log('ERR1resolvev4', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.A = addresses;
    });
    
    containers[domain].dns_scan.AAAA=[];
    dns.resolve6(domain, function(err, addresses) {
        //if (err) return console.log('err1resolvev6', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.AAAA = addresses;
    });
    
    containers[domain].dns_scan.MX=[];
    dns.resolveMx(domain, function(err, addresses) {
        //if (err) return console.log('err1resolveMx', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.MX = addresses;
    });
    
    containers[domain].dns_scan.NS=[];
    dns.resolveNs(domain, function(err, addresses) {
        //if (err) return console.log('err1resolveNs', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.NS = addresses; 
    });
    
    if (containers[domain].www_scan === undefined) containers[domain].www_scan = {};
    containers[domain].www_scan.A=[];
    dns.resolve4("www." + domain, function(err, addresses) {
        //if (err) return console.log('ERR1resolvev4', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.A = addresses;
    });
    
    containers[domain].www_scan.AAAA=[];
    dns.resolve6("www." + domain, function(err, addresses) {
        //if (err) return console.log('err1resolvev6', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.AAAA = addresses;
    });
    
    containers[domain].www_scan.MX=[];
    dns.resolveMx("www." + domain, function(err, addresses) {
        //if (err) return console.log('err1resolveMx', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.MX = addresses;
    });
    
    containers[domain].www_scan.NS=[];
    dns.resolveNs("www." + domain, function(err, addresses) {
        //if (err) return console.log('err1resolveNs', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.NS = addresses; 
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
