#!/bin/node

/*srvctl */

/*
    codepad/access.js — publish user credential files into the per-container
    share tree.

    Run by configure_codepad_access (this module's regenerate hook) as
    /bin/node access.js. For every container in the datastore, copies each
    authorized user's files matching *.hash and *.ip (in practice the
    dotfiles .hash/.ip written by the usersonhost module; never .password, of
    which only its SHA-512 is published, as .srvctl.hash) from
    $SC_DATASTORE_DIR/users/<u>/ into
    /var/srvctl3/share/containers/<c>/users/<u>/, which is bind-mounted
    read-only into the container so the in-container codepad server can
    authenticate srvctl users. Authorized users are: every user with
    access == "all", the container's primary user, each entry of the
    container's users[] list, and the primary user's reseller. root is
    always skipped.

    Exits 0 printing 'codepad: user and users access keys configured';
    a thrown error makes the wrapping exif abort the whole srvctl run.

    FIXME(v4): much of the scaffolding below (CMD, SC_UID0, hosts, resellers,
    out, return_value, return_error, output, the exitCode-99 dance) is unused
    here; the live logic is a near-duplicate of the ssh module's share-tree
    writer and should be unified in v4.
*/

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
var crypto = require('crypto');
var datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;

const os =  require('os');
const HOSTNAME = os.hostname();

const CMD = process.argv[2];
// constants
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;

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
    
    // FIXME(v4): side effect — creates empty datastore user directories for
    // any referenced user that has none (litter, and an unexpected write when
    // SC_DATASTORE_DIR resolves to a read-only replica).
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
    
    // The plaintext .password (also the user's host login password) is never
    // published: the share is readable by every process inside the container.
    // It stays in the root-only datastore. A copy left by an earlier version is
    // removed, because codepad reads .password BEFORE .hash and refuses the
    // login when one exists but cannot be read.
    for (i = 0; i < files.length; i++) {
        if (files[i].split('.')[1] === 'password' && fs.existsSync(dir + '/' + files[i])) fs.unlinkSync(dir + '/' + files[i]);
    }

    // What IS published of it is its SHA-512 hex as .srvctl.hash: the srvctl
    // login is what haproxy basic auth admits, so a service behind it (devpanel
    // proxy-user.mjs) can verify that same login. It is NOT .hash: that is the
    // codepad credential, which may be a different password the user set for
    // codepad, and both stay valid. Derived from .password on every run, so it
    // cannot drift from what haproxy checks.
    var passfile = SC_DATASTORE_DIR + "/users/" + u + "/.password";
    if (fs.existsSync(passfile)) {
        var login = fs.readFileSync(passfile, 'utf8').trim();
        if (login) fs.writeFileSync(dir + '/.srvctl.hash', crypto.createHash('sha512').update(login, 'utf8').digest('hex'));
    }
  
    var ip;
    for (i = 0; i < files.length; i++) { 
        if (files[i].split('.')[1] === 'ip') {
            ip = fs.readFileSync(SC_DATASTORE_DIR + "/users/" + u + "/" + files[i]);
            fs.writeFileSync(dir + '/' + files[i], ip);
        }
    }
}

function remake_access_keys(c) {
  
  	//  the user may have a special codepad all-access
  	Object.keys(users).forEach(function(u) {
    	if (users[u].access == "all") copy_access_keys(c,u);
    });
  
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
