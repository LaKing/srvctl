#!/bin/node

/*jshint esnext: true */

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
const execSync = require('child_process').execSync;

const CMD = process.argv[2];
// constatnts

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';
const SC_OPENDKIM_FOLDER = process.env.SC_DATASTORE_DIR + '/opendkim';

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

var TrustedHosts = '';
var SigningTable = '';
var KeyTable = '';

TrustedHosts += '127.0.0.1' + br;
TrustedHosts += '::1' + br;
TrustedHosts += '10.0.0.0/8' + br;

function run_domain(domain) {
    var selector = "default";
    if (domain.substring(0, 5) === 'mail.') selector = "mail";
    var private_file = "/srv/" + domain + "/opendkim/" + selector + ".private";
    var txt_file = "/srv/" + domain + "/opendkim/" + selector + ".txt";

    // we could check if container os in this host also via IP, we just check for the folder now.
    // make sure container has opendkim folder
    if (fs.existsSync("/srv/"+domain))
    if (!fs.existsSync(private_file)) {
        var opendkim_folder = '/srv/' + domain + '/opendkim';
        if (!fs.existsSync(opendkim_folder)) fs.mkdirSync(opendkim_folder);
        console.log('opendkim-genkey -D "' + opendkim_folder + '" -d "' + domain + '" -s "' + selector + '"');
        var code = execSync('opendkim-genkey -D "' + opendkim_folder + '" -d "' + domain + '" -s "' + selector + '"');
        console.log(code.toString('utf8'));
    }
    
    // sync it to the datastore
    if (fs.existsSync(private_file)) {
        var private = fs.readFileSync(private_file, 'UTF8');
        var target_folder = SC_OPENDKIM_FOLDER + '/' + domain;
        if (!fs.existsSync(target_folder)) fs.mkdirSync(target_folder);
        var target_file = SC_OPENDKIM_FOLDER + '/' + domain + '/' + selector + '.private';
        //if (! fs.existsSync(target_file)) 
        fs.writeFileSync(target_file, private);
    
        if (fs.existsSync(txt_file)) {
            var txt = fs.readFileSync(txt_file, 'UTF8');
            var p = txt.split('"')[3];
            containers[domain]['dkim-' + selector + '-domainkey'] = p;
        }
    }
    
    TrustedHosts += domain + br;
    KeyTable += selector + "._domainkey." + domain +" " + domain + ":" + selector + ":/var/opendkim/" + domain + "/" + selector + ".private" + br;
    SigningTable += "*@" + domain + " " + selector + "._domainkey." + domain + br;
}

function main() {
    Object.keys(containers).forEach(function(i) {
        if ((i.substr(i.length - 6) !== '.devel') && (i.substr(i.length - 6) !== '-devel') && (i.substr(i.length - 6) !== '.local') && (i.substr(i.length - 6) !== '-local'))
            run_domain(i);
    });
}

main();

process.exitCode = 0;

process.on('exit', function() {
    fs.writeFileSync(SC_OPENDKIM_FOLDER + '/TrustedHosts', TrustedHosts);
    fs.writeFileSync(SC_OPENDKIM_FOLDER + '/KeyTable', KeyTable);
    fs.writeFileSync(SC_OPENDKIM_FOLDER + '/SigningTable', SigningTable);
    fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
    msg('Wrote OpenDKIM TrustedHosts, KeyTable, SigningTable to ' + SC_OPENDKIM_FOLDER);
});

exit();
