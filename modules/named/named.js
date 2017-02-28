#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');

const CMD = process.argv[2];
// constatnts

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';

const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/users.json';
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
var hosts = {};
var users = {};
var resellers = {};
var containers = {};
var user = '';
var container = '';


//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions
function load_hosts() {
    try {
        hosts = JSON.parse(fs.readFileSync(SC_HOSTS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
    }
}
// data functions
function load_resellers() {
    resellers = {};
    resellers.root = users.root;
    resellers.root.is_reseller_id = 0;
    Object.keys(users).forEach(function(i) {
        if (users[i].is_reseller_id !== undefined)
            resellers[i] = users[i];
    });
}

function load_users() {
    try {
        users = JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
        if (users.root === undefined) {
            users.root = {};
            users.root.id = 0;
            users.root.uid = 0;
            users.root.reseller = 'root';
            users.root.is_reseller_id = 0;
        }
        // resellers are also users
        load_resellers();

    } catch (err) {
        return_error('READFILE ' + SC_USERS_DATA_FILE + ' ' + err);
    }
}

function load_containers() {
    try {
        containers = JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
    }
}


load_hosts();
load_containers();
load_users();

out('nothing');

exit();
