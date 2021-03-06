#!/bin/node

/*srvctl */

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

const CMD = process.argv[2];
// constatnts


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
    console.error('DATA-ERR R:', msg);
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

// data functions



function write_popmap_cfg() {
    var str = '';
    
    // 
    Object.keys(containers).forEach(function(i) {
        var dom = i;
        if (i.substring(0,5) === "mail.") dom  = i.substring(5);
        
        var mx = "mail." + i;
        if (i.substring(0,5) === "mail.") mx = i;
        
        
        str += "(.*)@" + dom + ": " + mx + br;
    });
    
    fs.writeFile('/var/perdition/popmap.re', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else {
            msg('datastore -> perdition popmap.re');
            exit();
        }
    });
}

write_popmap_cfg();



