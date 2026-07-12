#!/bin/node

/*srvctl */

/*
    dns/dns-scan.js — public-DNS scan of all container domains.

    Run synchronously by dns_scan (libs/bashlib.sh) from this module's
    regenerate hook. For every container in the datastore and every domain
    from datastore.container_domains() (container name if it contains a
    dot, plus aliases/altnames, each with a www. variant), resolves A —
    then, inside the A success callback, AAAA, MX and NS — against 8.8.8.8
    and stores the results as
        containers[name].dns[domain] = { A, AAAA, MX, NS,
            timestamp: { time: <epoch seconds>,
                         state: "OK" | "UNKNOWN" | <node dns err.code> } }
    Domains whose last state was ENOTFOUND, ETIMEOUT or ESERVFAIL are
    re-scanned at most hourly; everything else on every run. On process
    exit the whole in-memory containers object is written back to
    $SC_DATASTORE_DIR/containers.json (2-space pretty-printed). The
    letsencrypt module reads this data to decide whether a domain points
    at this host before requesting certificates. Exits 0 on any normal
    run; a nonzero exit would abort the whole srvctl run via the hook's
    exif.

    FIXME(v4): much of the scaffolding below (CMD, SRVCTL, SC_UID0,
    HOSTNAME, localhost, br, out, return_value, return_error, output,
    hosts, users, resellers, user, container, the exitCode-99 dance) is
    unused copy-paste boilerplate shared with other modules' JS files;
    a shared ESM datastore/context module should replace it in v4.
*/

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;

function out(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

const CMD = process.argv[2];
// constants

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
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

// FIXME(v4): low — resolver hardcoded to the single upstream 8.8.8.8,
// bypassing the system resolver and the local named module; if Google DNS
// is unreachable every domain flips to ETIMEOUT (wiping stored records,
// see below) and letsencrypt is blocked cluster-wide. Needs a config knob
// (e.g. SC_DNS_UPSTREAM).
const { Resolver } = require('dns');
const dns = new Resolver();
dns.setServers(['8.8.8.8']);

const NOW = new Date().toISOString();
const NOW_T = Math.floor(Date.now() / 1000);

// ENOTFOUND > not registered?
// ETIMEOUT > not registered and no authority:

// data functions

function scan_container(name) {
  	let domains = datastore.container_domains(name);
    for (let n in domains) {
        scan_container_domain(name, domains[n]);
    }
}

function scan_container_domain(name, domain) {
    // some sanity check, probably redundant
    if (!containers[name]) return console.log("No container for " + domain);
    // ensure object exists
    if (containers[name].dns === undefined) containers[name].dns = {};
    // reset the scan
    if (!containers[name].dns[domain]) containers[name].dns[domain] = {};
    // create a reference
    var o = containers[name].dns[domain];
    // create datapoints
    // FIXME(v4): medium — records are reset to [] before the hourly-skip
    // check below and before the async resolution completes, so a transient
    // resolver failure (or a skipped problematic domain) leaves previously
    // good records wiped in the containers.json written at exit;
    // letsencrypt then sees A=[] and refuses issuance/renewal until a
    // later successful scan. v4 should keep old records on error.
    o.A = [];
    o.AAAA = [];
    o.MX = [];
    o.NS = [];

    if (o.timestamp === undefined) o.timestamp = {};
    if (!o.timestamp.time) o.timestamp.time = 0;

    // scan problematic domains hourly
    if (NOW_T - o.timestamp.time < 3600) {
        if (o.timestamp.state === "ENOTFOUND") return console.log("Skipping DNS scan on ENOTFOUND " + name + " " + domain);
        if (o.timestamp.state === "ETIMEOUT") return console.log("Skipping DNS scan on ETIMEOUT " + name + " " + domain);
        if (o.timestamp.state === "ESERVFAIL") return console.log("Skipping DNS scan on ESERVFAIL " + name + " " + domain);
    }
	
    o.timestamp.time = NOW_T;
    o.timestamp.state = "UNKNOWN";

    dns.resolve4(domain, function (err, addresses) {
        if (err) {
            ntc("DNS Scan A record", err.code, err.hostname);
            o.timestamp.state = err.code;
            return;
        }

        o.timestamp.state = "OK";
        if (addresses !== undefined) o.A = addresses;

        // FIXME(v4): medium — AAAA/MX/NS lookups run only inside the
        // resolve4 success callback: domains with no A record (e.g.
        // IPv6-only, ENODATA) never get AAAA/MX/NS data, and since ENODATA
        // is not in the skip list above they are re-queried fruitlessly on
        // every run. v4 should resolve all four record types independently.
        // Errors of the three lookups below are deliberately ignored.

        dns.resolve6(domain, function (err, addresses) {
            if (addresses !== undefined) o.AAAA = addresses;
        });

        dns.resolveMx(domain, function (err, addresses) {
            if (addresses !== undefined) o.MX = addresses;
        });

        dns.resolveNs(domain, function (err, addresses) {
            if (addresses !== undefined) o.NS = addresses;
        });

    });
}

function scan() {
    Object.keys(containers).forEach(function (i) {
        scan_container(i);
    });
}

scan();

process.exitCode = 0;

// The exit handler fires once the event loop drains, i.e. after all
// pending resolver callbacks above have completed or errored.
// FIXME(v4): medium — unconditional writeFileSync of the entire stale
// in-memory containers object: no lock and no SC_DATASTORE_RO check
// (unlike write_containers in datastore/lib.js), so any concurrent
// containers.json writer — another srvctl command on this host, or
// another cluster host when the datastore is the shared gluster mount —
// is silently clobbered with the copy loaded at startup.
process.on("exit", function () {
    datastore.save_type("containers", containers); // was monolithic write, lost on v4 per-entity
});

exit();
