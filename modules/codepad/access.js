#!/bin/node

/*srvctl */

function out(msg) {
    console.log(msg);
}

const lablib = '../../lablib.js';
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

// includes
var fs = require('fs');
var datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;

const os =  require('os');
const HOSTNAME = os.hostname();

const CMD = process.argv[2];
// constatnts
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;

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


function copy_access_keys(c,u) {
    if (u === 'root') return;

    var i;

    var dir = '/var/srvctl3/share/containers/' + c;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    
    dir = SC_DATASTORE_DIR + "/users/" + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    
    dir = '/var/srvctl3/share/containers/' + c + '/users';
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    dir = '/var/srvctl3/share/containers/' + c + '/users/' + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }

    var files = fs.readdirSync(SC_DATASTORE_DIR + "/users/" + u);
 
    var hash;
    for (i = 0; i < files.length; i++) { 
        if (files[i].split('.')[1] === 'hash') {
            hash = fs.readFileSync(SC_DATASTORE_DIR + "/users/" + u + "/" + files[i]);
            fs.writeFileSync(dir + '/' + files[i], hash);
        }
    }
    
    var password;
    for (i = 0; i < files.length; i++) { 
        if (files[i].split('.')[1] === 'password') {
            password = fs.readFileSync(SC_DATASTORE_DIR + "/users/" + u + "/" + files[i]);
            fs.writeFileSync(dir + '/' + files[i], password);
        }
    }

}

function remake_access_keys(c) {
    if (containers[c].user === undefined) return;
    
    // primary user
    copy_access_keys(c,containers[c].user);
    
    // other users (developers, guests, people that are allowed to have root access)
    if (containers[c].users !== undefined) {   
        for (var i = 0; i < containers[c].users.length; i++) { 
            copy_access_keys(c,containers[c].users[i]);
        }
    }
    
    // reseller
    if (users[containers[c].user] === undefined) return;
    if (users[containers[c].user].reseller === undefined) return;
    copy_access_keys(c,users[containers[c].user].reseller);
    
}

function user_access() {
    Object.keys(containers).forEach(function(c) {
            remake_access_keys(c);
    });
}



user_access();

process.exitCode = 0;

process.on('exit', function() {
    msg('codepad: user and users access keys configured');
});

exit();
