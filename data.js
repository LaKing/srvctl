#!/bin/node

/*jshint esnext: true */

const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];

// constatnts
const SC_USERS_DATA_FILE = '/etc/srvctl/users.json';
const SC_CONTAINERS_DATA_FILE = '/etc/srvctl/containers.json';

const CONTAINER = 'container';
const USER = 'user';

const PUT = 'put';
const GET = 'get';
const OUT = 'out';

const IP = 'ip';

function exit() {
    process.exit(0);
}

function return_value(msg) {
    console.log(msg);
    process.exit(0);
}

function return_error(msg) {
    console.error('ERROR:', msg);
    process.exit(10);
}

function output(variable, value) {
    console.log(variable + '=' + value);
}

// get or put
if (CMD === undefined) return_error("MISSING CMD ARGUMENT");
// users or containers
if (DAT === undefined) return_error("MISSING DAT ARGUMENT");
// field
if (ARG === undefined) return_error("MISSING ARG ARGUMENT");
// OPA is optional

if (CMD !== GET && CMD !== PUT && CMD !== OUT) return_error("INVALID CMD ARGUMENT");
if (DAT !== USER && DAT != CONTAINER) return_error("INVALID DAT ARGUMENT");

// includes
var fs = require('fs');

// variables
var users = [];
var containers = {};
var user = '';
var container = '';

//if (DAT === CONTAINER) container = ARG;
//if (DAT === USER) user = ARG;


// data functions
function load_users() {
    try {
        users = JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_USERS_DATA_FILE);
    }
}

function load_containers() {
    try {
        containers = JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_CONTAINERS_DATA_FILE);
    }
}

function save_users() {
    try {
        fs.writeFileSync(SC_USERS_DATA_FILE, JSON.stringify(users));
    } catch (err) {
        return_error('WRITEFILE ' + SC_USERS_DATA_FILE);
    }
}

function save_containers() {
    try {
        fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers));
    } catch (err) {
        return_error('WRITEFILE ' + SC_CONTAINERS_DATA_FILE);
    }
}

if (DAT === CONTAINER) {

    load_containers();

    if (CMD === PUT && DAT === CONTAINER) {
        if (containers[ARG] !== undefined) return_error('CONTAINER EXISTS');
        var container = {};
        // TODO get next IP available
        container.ip = '10.11.12.13';
        containers[ARG] = container;
        save_containers();
        exit();
    }

    if (CMD == GET) {
        if (containers[ARG] === undefined) return_error('CONTAINER DONT EXISTS');
        var container = containers[ARG];
        if (OPA === IP) return_value(container.ip);

    }

    if (CMD == OUT) {
        if (containers[ARG] === undefined) return_error('CONTAINER DONT EXISTS');
        var container = containers[ARG];
        output('name', ARG);
        // .. all possible fields
        output(IP, container.ip);

        // ...
        exit();
    }
}

return_error("EXIT on EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);