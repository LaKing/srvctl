#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');
var datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;

const CMD = process.argv[2];
// constatnts
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const HOSTNAME = process.env.HOSTNAME;
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

function copy_user_key(c,u) {
    
    var key =  fs.readFileSync(SC_DATASTORE_DIR + "/users/" + u + "/authorized_keys");
    
    var dir = '/var/srvctl3/share/containers/' + c;
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

    fs.writeFileSync(dir + '/authorized_keys', key);

}

function remake_ssh_keys(c) {
    copy_user_key(c,containers[c].user);
}

function main() {
    Object.keys(containers).forEach(function(i) {
            remake_ssh_keys(i);
    });
}

function system_ssh_config() {
    var str = '## ssh_config' + br;
        str += "Host localhost" + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "" + br;
        
        str += "Host 127.0.0.1" + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "" + br;
    
    //Object.keys(hosts).forEach(function(i) {
    //    str += "Host " + i + br;
        //str += "User root" + br;
        //str += "StrictHostKeyChecking no" + br;
        str += "" + br;
    //});
    Object.keys(containers).forEach(function(i) {
        str += "Host " + i + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "" + br;
    });
    fs.writeFile('/etc/ssh/ssh_config.d/srvctl-containers.conf', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] ssh srvctl-containers.conf');
    });
}

system_ssh_config();

main();

process.exitCode = 0;

process.on('exit', function() {

});

exit();
