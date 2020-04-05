#!/bin/node

/*srvctl */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

const CMD = process.argv[2];
// constatnts

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os = require("os");
const HOSTNAME = os.hostname();
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
var containers = datastore.containers;
var user = "";
var container = "";

const dns = require("dns");
const NOW = new Date().toISOString();
const NOW_T = Math.floor(Date.now() / 1000);

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// ENOTFOUND > not registered?
// ETIMEOUT > not registered and no authority:

// data functions

function scan_prepare(domain) {
    if (containers[domain].dns_scan === undefined) containers[domain].dns_scan = {};
    containers[domain].dns_scan.A = [];
    containers[domain].dns_scan.AAAA = [];
    containers[domain].dns_scan.MX = [];
    containers[domain].dns_scan.NS = [];

    if (containers[domain].www_scan === undefined) containers[domain].www_scan = {};
    containers[domain].www_scan.A = [];
    containers[domain].www_scan.AAAA = [];
    containers[domain].www_scan.MX = [];
    containers[domain].www_scan.NS = [];
}

function scan_domain(domain) {
    if (domain.indexOf(".") < 0) return;
    if (!containers[domain]) return console.log("No container for " + domain);

    scan_prepare(domain);

    if (containers[domain].dns_query === undefined) containers[domain].dns_query = {};

    // scan problematic domains only once a day
    if (NOW_T - containers[domain].dns_query.time < 43200) {
        if (containers[domain].dns_query.state === "ENOTFOUND") return console.log("Skipping DNS scan on ENOTFOUND " + domain);
        if (containers[domain].dns_query.state === "ETIMEOUT") return console.log("Skipping DNS scan on ETIMEOUT " + domain);
        if (containers[domain].dns_query.state === "ESERVFAIL") return console.log("Skipping DNS scan on ESERVFAIL " + domain);
    }

    containers[domain].dns_query.time = NOW_T;
    containers[domain].dns_query.state = "UNKNOWN";

    dns.resolve4(domain, function(err, addresses) {
        if (err) {
            //if (err) return console.log('ERR1resolvev4', err.code, err.hostname);
            console.log("DNS Scan A record", err.code, err.hostname);
            containers[domain].dns_query.state = err.code;
            return;
        }

        containers[domain].dns_query.state = "OK";
        if (addresses !== undefined) containers[domain].dns_scan.A = addresses;

        scan_domain_extended(domain);
    });
}

function scan_domain_extended(domain) {
    if (containers[domain].dns_scan === undefined) containers[domain].dns_scan = {};

    dns.resolve6(domain, function(err, addresses) {
        //if (err) return console.log("err1resolvev6", err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.AAAA = addresses;
    });

    dns.resolveMx(domain, function(err, addresses) {
        //if (err) return console.log('err1resolveMx', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.MX = addresses;
    });

    dns.resolveNs(domain, function(err, addresses) {
        //if (err) return console.log('err1resolveNs', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].dns_scan.NS = addresses;
    });

    dns.resolve4("www." + domain, function(err, addresses) {
        //if (err) return console.log('ERR1resolvev4', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.A = addresses;
    });

    dns.resolve6("www." + domain, function(err, addresses) {
        //if (err) return console.log('err1resolvev6', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.AAAA = addresses;
    });

    dns.resolveMx("www." + domain, function(err, addresses) {
        //if (err) return console.log('err1resolveMx', err.code, err.hostname);
        if (addresses !== undefined) containers[domain].www_scan.MX = addresses;
    });

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

process.on("exit", function() {
    fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
});

exit();
