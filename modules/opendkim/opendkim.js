#!/bin/node

/*
 * modules/opendkim/opendkim.js — DKIM key and table generator.
 *
 * Run as root by opendkim_main (libs/bashlib.sh) on every regenerate.
 * For each container domain not ending in .devel/-devel/.local/-local:
 *   - the selector is 'mail' for domains starting with 'mail.', else
 *     'default' (key filenames, table entries, the datastore keys and
 *     the named module's zone records all depend on this rule);
 *   - if /srv/<domain> exists on this host and the private key is
 *     missing, generate one with opendkim-genkey into
 *     /srv/<domain>/opendkim/ (existing keys are never regenerated —
 *     DNS holds the public half);
 *   - copy the private key into $SC_DATASTORE_DIR/opendkim/<domain>/
 *     (overwritten every run: /srv is authoritative on the owning
 *     host) and publish the public key — with its literal 'p=' prefix —
 *     into containers.json as 'dkim-<selector>-domainkey', consumed by
 *     modules/named/named.js for the DNS TXT record;
 *   - append the domain to TrustedHosts and KeyTable.
 * A domain-only record (domain_only=true, retire-ve) has no container files:
 * its key is the host-side copy in $SC_DATASTORE_DIR/opendkim/<domain>/, which
 * retire-ve preserved. It is never generated, never copied over and its
 * published dkim-<selector>-domainkey is never rewritten (lib/keys.js).
 * Who may sign which domain comes from lib/entitlement.js (EntitledSigners,
 * SignableDomains, HostSigningTable, InternalHosts, EmptySigningTable); the
 * wildcard SigningTable of earlier versions (every domain for every
 * internal client) is no longer written. TrustedHosts is only the
 * ExternalIgnoreList now. The selector rule also lives in
 * conf/signing-policy.lua.
 * On exit the table files and containers.json are written back to the
 * datastore; the bash side (libs/opendkimlib.sh) then mirrors the folder
 * to /var/opendkim and restarts opendkim.service if it changed, and
 * regenerate_opendkim_conf sets the keys of /etc/opendkim.conf.
 * A nonzero exit aborts the whole srvctl run via exif.
 */

/*srvctl */

// FIXME(v4): most of the shared datastore-js boilerplate below is dead
// in this script (ntc, err, get, run, rok, out, CMD, SC_UID0, localhost,
// hosts, users, resellers, user, container, exit/return_value/
// return_error/output and the exitCode=99 ceremony); only msg, fs,
// datastore, execSync and the SC_* paths are actually used.
const lablib = '../../lablib.js';
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
var fs = require('fs');
var datastore = require('../datastore/lib.js');
const entitlement = require('./lib/entitlement.js');
const keys = require('./lib/keys.js');
const execSync = require('child_process').execSync;

const CMD = process.argv[2];
// constants

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';
const SC_OPENDKIM_FOLDER = process.env.SC_DATASTORE_DIR + '/opendkim';

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const os =  require('os');
const HOSTNAME = os.hostname();
const localhost = 'localhost';
const br = '\n';
// Sentinel: stays 99 if an exception aborts the script before the end.
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

var TrustedHosts = '';
var KeyTable = '';

// TrustedHosts (ExternalIgnoreList only: it silences the "external host
// tried to send as" log lines) seed: loopback plus the 10.0.0.0/8 farm
// network; every hosted domain is appended in run_domain below.
TrustedHosts += '127.0.0.1' + br;
TrustedHosts += '::1' + br;
TrustedHosts += '10.0.0.0/8' + br;

function run_domain(domain) {
    var plan = keys.key_plan({
        domain: domain,
        record: containers[domain],
        srvRoot: '/srv',
        opendkimFolder: SC_OPENDKIM_FOLDER,
        exists: fs.existsSync,
    });
    var selector = plan.selector;
    var private_file = plan.private_file;
    var txt_file = plan.txt_file;

    // A domain-only record signs with its preserved host-side key; nothing
    // under /srv counts, a leftover directory included.
    if (plan.action === 'missing') err('DKIM key of the domain-only record ' + domain + ' is missing: ' + plan.hostside_file + ' (restore it from the retire-ve backup)');

    // A /srv/<domain> folder is our only sign the container lives on
    // this host (an IP check would be more precise). Make sure the
    // container has an opendkim folder and a key, generating one only
    // when the private key file is absent.
    // FIXME(v4): low — the domain name is interpolated unescaped into a
    // root shell command; a corrupted containers.json key containing '"'
    // or '$(...)' executes arbitrary shell as root.
    if (plan.action === 'genkey') {
        var opendkim_folder = plan.opendkim_folder;
        if (!fs.existsSync(opendkim_folder)) fs.mkdirSync(opendkim_folder);
        console.log('opendkim-genkey -D "' + opendkim_folder + '" -d "' + domain + '" -s "' + selector + '"');
        var code = execSync('opendkim-genkey -D "' + opendkim_folder + '" -d "' + domain + '" -s "' + selector + '"');
        console.log(code.toString('utf8'));
    }

    // Sync the private key to the datastore (always overwritten: the
    // /srv copy is authoritative here) and publish the public key.
    // NOTE: 'private' is a reserved word — parses in sloppy mode only,
    // would be a SyntaxError under "use strict"/ESM.
    if ((plan.action === 'genkey' || plan.action === 'copy') && fs.existsSync(private_file)) {
        var private = fs.readFileSync(private_file, 'UTF8');
        var target_folder = SC_OPENDKIM_FOLDER + '/' + domain;
        if (!fs.existsSync(target_folder)) fs.mkdirSync(target_folder);
        var target_file = SC_OPENDKIM_FOLDER + '/' + domain + '/' + selector + '.private';
        fs.writeFileSync(target_file, private);

        // FIXME(v4): medium — txt.split('"')[3] assumes opendkim-genkey
        // emits the public key as a single quoted chunk; keys over 255
        // bytes (e.g. generated with -b 2048) come as multiple quoted
        // strings, so only the first chunk is stored and named publishes
        // a truncated p= — DKIM validation fails with no error anywhere.
        // If the .txt layout differs, [3] is undefined and
        // JSON.stringify silently drops a previously valid
        // dkim-*-domainkey from containers.json (DNS record removed on
        // the next named regenerate).
        if (fs.existsSync(txt_file)) {
            var txt = fs.readFileSync(txt_file, 'UTF8');
            var p = txt.split('"')[3];
            containers[domain]['dkim-' + selector + '-domainkey'] = p;
        }
    }

    // FIXME(v4): low — table lines are appended even when the key is not
    // in the datastore yet (container added on another host before its
    // regenerate), so KeyTable can reference missing
    // /var/opendkim/<domain>/<selector>.private files until the owning
    // host regenerates and the datastore syncs.
    TrustedHosts += domain + br;
    KeyTable += selector + "._domainkey." + domain +" " + domain + ":" + selector + ":/var/opendkim/" + domain + "/" + selector + ".private" + br;
}

function main() {
    // Skip development and cluster-internal domains entirely.
    Object.keys(containers).forEach(function(i) {
        if (entitlement.signable(i)) run_domain(i);
    });
}

main();

process.exitCode = 0;

// Registered only after main() succeeded: an exception above leaves the
// exitCode=99 sentinel and writes nothing.
// FIXME(v4): medium — containers.json is rewritten wholesale from the
// snapshot loaded at process start, with no locking or change detection:
// a concurrent srvctl change to containers.json is silently reverted,
// and the shared datastore file is dirtied on every regenerate even when
// nothing changed.
process.on('exit', function() {
    fs.writeFileSync(SC_OPENDKIM_FOLDER + '/TrustedHosts', TrustedHosts);
    fs.writeFileSync(SC_OPENDKIM_FOLDER + '/KeyTable', KeyTable);
    const tables = entitlement.tables(entitlement.entitlement({ containers: containers, hosts: hosts, SC_COMPANY_DOMAIN: process.env.SC_COMPANY_DOMAIN }));
    Object.keys(tables).forEach(function(name) {
        fs.writeFileSync(SC_OPENDKIM_FOLDER + '/' + name, tables[name]);
    });
    datastore.save_type("containers", containers); // was monolithic write, lost on v4 per-entity
    msg('Wrote OpenDKIM TrustedHosts, KeyTable, ' + Object.keys(tables).join(', ') + ' to ' + SC_OPENDKIM_FOLDER);
});

exit();
