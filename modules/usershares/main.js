#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
const fs = require('fs');
const datastore = require('../datastore/lib.js');
const password_lib = require('../password/lib.js');

const lablib = '../../lablib.js';
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

const execSync = require('child_process').execSync;
const CMD = process.argv[2];
// constatnts


const SRVCTL = process.env.SRVCTL;
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;
const os = require('os');
const HOSTNAME = os.hostname();
const localhost = 'localhost';
const br = '\n';
const root = "root";
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
    console.error('main.js ERR:', msg);
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


//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

/*


console.log("usershares");

/*
// a js based implementation
function crate_user_password(user) {
    
    var userdata = SC_DATASTORE_DIR + "/users/" + user;
    var passfile = userdata + "/.password";
    var password;
    if (fs.existsSync(passfile)) password = fs.readFileSync(passfile, 'utf8').trim();
    if (password === undefined) password = password_lib.get_password();
    if (password.length < 10) password = password_lib.get_password();
    
        
    fs.writeFileSync(passfile, password);
    
    msg("Password-update for user: " + user + " password: " + password);
    run("echo " + password + " | passwd " + user + " --stdin 2> /dev/null 1> /dev/null");
    run("echo " + password + " > $(getent passwd " + user + " | cut -f6 -d:)/.password");
   
}
*/

var mounts = get("mount");

function make_share(u, c) {
    //msg("Match " + c + " to " + u );
    var getent = get("getent passwd " + u);
    
    var dir = getent.split(':')[5] + '/' + c;
    
    if (!fs.existsSync(dir)) fs.mkdirSync(dir);
    var host = datastore.container_host(containers[c]);
    
    //var source_path = "/srv/" + c + "/rootfs";
    //if (host !== HOSTNAME) 
    var source_path = "/var/srvctl3/nfs/" + host + "/srv/" + c + "/rootfs";
    if (!fs.existsSync(dir + '/bindfs')) fs.mkdirSync(dir + '/bindfs');
    if (fs.existsSync(source_path) && mounts.indexOf(source_path + " on " + dir + "/bindfs type fuse") === -1)
    run("bindfs -m " + u + " " + source_path + " " + dir + "/bindfs");

}


Object.keys(users).forEach(function(u) {
    if (u === root) return;

    if (!rok("id " + u)) {
        run("adduser " + u);
    }
});

Object.keys(containers).forEach(function(c) {
    make_share(containers[c].user, c);
    make_share(datastore.container_reseller_user(containers[c]), c);
});


exit();
