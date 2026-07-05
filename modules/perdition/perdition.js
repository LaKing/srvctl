#!/bin/node

/*srvctl */

// modules/perdition/perdition.js — regenerate the perdition routing map.
//
// Invoked by perditioncfg (libs/bashlib.sh) on every container
// regenerate: writes /var/perdition/popmap.re with one line per
// datastore container, '(.*)@<domain>: mail.<domain>' (a container
// already named mail.* maps to itself), consumed by perdition's
// posix_regex map library.
//
// Exit-code protocol (farm-wide datastore-script convention):
//   0 = success, 99 = sentinel if the async write callback never runs,
//   100 = empty return value, 111 = write error (DATA-ERR R:),
//   112 = datastore lib LIB-ERROR (unreadable JSON).
//
// FIXME(v4): most of this file is copy-pasted datastore-module
// boilerplate (unused imports, constants and helpers are marked
// below); the G9 mail proxy replaces it — in v4 this collapses to a
// few lines mapping Object.keys(containers) to popmap lines.

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
// FIXME(v4): low — ntc, get, run, rok, err are imported but unused.
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

// FIXME(v4): low — out() is dead code, never called.
function out(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

// FIXME(v4): low — CMD, SRVCTL, SC_UID0, HOSTNAME, localhost are
// unused boilerplate constants.
const CMD = process.argv[2];
// constatnts

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const os = require("os");
const HOSTNAME = os.hostname();
const localhost = "localhost";
const br = "\n";
// Sentinel: stays 99 unless the write callback runs exit()/return_error().
process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

// FIXME(v4): low — return_value() and output() are dead code, never
// called; only exit() and return_error() are used here.
function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error("DATA-ERR R:", msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}

// variables
// FIXME(v4): low — hosts, users, resellers, user, container are unused;
// only containers is read.
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var user = "";
var container = "";

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions

function write_popmap_cfg() {
    var str = "";

    //
    Object.keys(containers).forEach(function (i) {
        var dom = i;
        if (i.substring(0, 5) === "mail.") dom = i.substring(5);

        var mx = "mail." + i;
        if (i.substring(0, 5) === "mail.") mx = i;

        // FIXME(v4): low — dom is interpolated into the regex
        // unescaped ('.' matches any char); duplicate lines are
        // emitted when both example.com and mail.example.com
        // containers exist; and every container (including pure web
        // sites) gets mapped to a possibly nonexistent mail.<domain>.
        str += "(.*)@" + dom + ": " + mx + br;
    });

    fs.writeFile("/var/perdition/popmap.re", str, function (err) {
        if (err) return_error("WRITEFILE " + err);
        else {
            msg("datastore -> perdition popmap.re");
            exit();
        }
    });
}

write_popmap_cfg();
