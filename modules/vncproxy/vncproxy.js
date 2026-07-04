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
const SC_UID0 = process.env.SC_UID0;
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
//var containers = {};
//var user = '';
//var container = '';

var use_codepad = false;
if (process.env.SC_USE_CODEPAD === "true") use_codepad = true;

const chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#*+-.,:;<=>_?@".split("");

function hash(...strings) {
    const blocks = [];
    for (const s of strings) {
        let h = 9;
        for (let i = 0; i < s.length; ) h = Math.imul(h ^ s.charCodeAt(i++), 9 ** 9);
        const base = Math.abs(h ^ (h >>> 9))
            .toString(10)
            .padStart(10, "0");

        let result = [];
        result.push(chars[Number(base.substring(0, 3)) % chars.length]);
        result.push(chars[Number(base.substring(2, 5)) % chars.length]);
        result.push(chars[Number(base.substring(4, 7)) % chars.length]);
        result.push(chars[Number(base.substring(6, 9)) % chars.length]);
        blocks.push(result.join(""));
    }
    return blocks.join("").substring(0, 8);
}

const records = [];

const containers = datastore.containers;
for (const C in containers) {
    if (containers[C].vncusers)
        for (const vncuser of containers[C].vncusers) {
            const password = hash(C, vncuser);
            records.push('record "' + password + '" "' + C + ':5900" "null" "' + vncuser + " @ " + C + '"');
        }
}


function write_proxy_cfg() {
    fs.writeFile("/var/vncproxy/records", records.join('\n'), function (err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("wrote vncproxy conf");
    });
}

write_proxy_cfg();

const arg_container = process.argv[2];
const arg_vncuser = process.argv[3];

msg("User added. container: " + arg_container + " vncuser: " + arg_vncuser + " host: " + HOSTNAME + " password: " + hash(arg_container, arg_vncuser));

process.exitCode = 0;

exit();
