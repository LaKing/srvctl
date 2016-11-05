#!/bin/node

/*jshint esnext: true */

function log(msg) {
    console.log(msg);
}

const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];

// constatnts
const SC_USERS_DATA_FILE = '/etc/srvctl/users.json';
const SC_CONTAINERS_DATA_FILE = '/etc/srvctl/containers.json';

const PUT = 'put';
const GET = 'get';
const OUT = 'out';
const dot = '.';
// netblock size
const NBC = 16;

if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

if (process.env.NOW !== undefined) NOW = process.env.NOW;
else NOW = new Date().toISOString();

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const HOSTNAME = process.env.HOSTNAME;


function exit() {
    if (save_containers) write_containers();
    if (save_users) write_users();
    process.exit(0);
}

function return_value(msg) {
    console.log(msg);
    process.exit(0);
}

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
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
if (DAT !== 'user' && DAT != 'container') return_error("INVALID DAT ARGUMENT");

// includes
var fs = require('fs');

// variables
var users = [];
var containers = {};
var user = '';
var container = '';
var save_users = false;
var save_containers = false;

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;


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

function write_users() {
    try {
        fs.writeFileSync(SC_USERS_DATA_FILE, JSON.stringify(users, null, 2));
    } catch (err) {
        return_error('WRITEFILE ' + SC_USERS_DATA_FILE);
    }
}

function write_containers() {
    try {
        fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
    } catch (err) {
        return_error('WRITEFILE ' + SC_CONTAINERS_DATA_FILE);
    }
}


/* ------------------- //
SC CONTAINER NETBLOCKS (16)

0: network address
1: containers
...
10: containers
11: spare
12: spare
13: reserved
14: bridge ip
15: broadcast address

/* -------------------- */

function ip_to_network_adress(ip) {
    var a = ip.split(dot);
    return Number(a[0]) + dot + Number(a[1]) + dot + Number(a[2]) + dot + Number(NBC * Math.trunc(a[3] / NBC));
}

function ip_to_bridge_address(ip) {
    var a = ip.split(dot);
    return Number(a[0]) + dot + Number(a[1]) + dot + Number(a[2]) + dot + Number((NBC - 2) + NBC * Math.trunc(a[3] / NBC));
}

function has_container_in_netblock(n1, n2, n3) {

    var result = false;

    Object.keys(containers).forEach(function(i) {

        var a = containers[i].ip.split(dot);

        var a1 = Number(a[1]);
        var a2 = Number(a[2]);
        var a3 = Number(a[3]);

        // switch to netblock address        
        a3 = NBC * Math.trunc(a3 / NBC);

        if (n1 === a1 && n2 === a2 && n3 === a3) {
            result = true;
        }
    });

    return result;

}

function find_first_free_netblock() {

    // find the highest netblock, and simply take the next one.

    // first, find last netblock
    var n1 = 20;
    var n2 = 0;
    var n3 = 0;

    while (n1 < 255) {

        if (!has_container_in_netblock(n1, n2, n3)) break;

        // so increment now with one netblock
        n3 += NBC;

        if (n3 > 240) {
            n3 = 0;
            n2++;
        }
        if (n2 > 255) {
            n2 = 0;
            n1++;
        }
        if (n1 > 255) {
            return_error("Owerflow - could not allocate next netblock");
        }
    }

    return '10.' + n1 + dot + n2 + dot + n3;

}

function find_next_free_netblock() {

    // find the highest netblock, and simply take the next one.

    // first, find last netblock
    var n1 = 20;
    var n2 = 0;
    var n3 = 0;

    Object.keys(containers).forEach(function(i) {

        var a = containers[i].ip.split(dot);

        var a1 = Number(a[1]);
        var a2 = Number(a[2]);
        var a3 = Number(a[3]);

        // switch not netblock address        
        a3 = NBC * Math.trunc(a3 / NBC);

        if (a1 > n1) {
            n1 = a1;
            n2 = a2;
            n3 = a3;
            return;
        }
        if (a1 === n1 && a2 > n2) {
            n1 = a1;
            n2 = a2;
            n3 = a3;
            return;
        }
        if (a1 === n1 && a2 === n2 && a3 > n3) {
            n1 = a1;
            n2 = a2;
            n3 = a3;
            return;
        }
    });

    // so increment now with one netblock
    n3 += NBC;

    if (n3 > 240) {
        n3 = 0;
        n2++;
    }
    if (n2 > 255) {
        n2 = 0;
        n1++;
    }
    if (n1 > 250) return find_first_free_netblock();
    // or ..
    // if (n1 > 255) return_error("Owerflow - could not allocate next netblock");

    return '10.' + n1 + dot + n2 + dot + n3;

}

function find_ip_for_container() {
    var b = find_next_free_netblock();
    var a = b.split(dot);
    return '10.' + a[1] + dot + a[2] + dot + String(Number(a[3]) + 1);
}

function new_user(username) {
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;
    user.projects = {};
    users[username] = user;
    save_users = true;
}

function add_project_to_user(P, U) {
    if (users[U] === undefined) new_user(U);
    var user = users[U];
    if (user.projects === undefined) user.projects = {};
    var projects = user.projects;
    if (projects[P] === undefined) {
        var project = {};
        project.host = HOSTNAME;
        project.netblock = find_next_free_netblock();
        project.containers = [];
        save_users = true;
        return project;
    }

    return projects[P];
}

function add_container_to_user(C, U) {
    if (users[U] === undefined) new_user(U);
    var user = users[U];
    if (user.projects === undefined) user.projects = {};

    var user_has_it = false;
    Object.keys(user.projects).forEach(function(i) {
        var p = user.projects[i];
        // if this project has this container
        if (p.containers !== undefined && p.containers.indexOf(C) > -1) user_has_it = true;
    });

    if (user_has_it) return;

    // new project, new container ...
    var project = add_project_to_user(C, U);
    project.containers.push(C);
    save_users = true;

}

function new_container(C, U) {

    add_container_to_user(C, U);

    var container = {};

    container.ip = find_ip_for_container();
    //container.owner = SC_USER;
    container.creation_time = NOW;
    containers[C] = container;
    save_containers = true;


}

load_containers();
load_users();

if (DAT === 'container') {

    if (CMD === PUT) {
        if (containers[ARG] !== undefined) return_error('CONTAINER EXISTS');
        new_container(ARG, SC_USER);
        exit();
    }

    if (CMD == GET) {
        if (OPA === 'exist') return_value(containers[ARG] !== undefined);
        if (containers[ARG] === undefined) return_error('CONTAINER DONT EXISTS');
        var container = containers[ARG];
        if (OPA === 'ip') return_value(container.ip);
        if (OPA === 'br') return_value(ip_to_bridge_address(container.ip));

    }

    if (CMD == OUT) {
        if (containers[ARG] === undefined) return_error('CONTAINER DONT EXISTS');
        var container = containers[ARG];
        output('name', ARG);
        // .. all possible fields
        output('ip', container.ip);
        // ...
        exit();
    }
}

if (DAT === 'user') {

    if (CMD === PUT) {
        if (users[ARG] !== undefined) return_error('USER EXISTS');
        new_user(ARG);
        exit();
    }

    if (CMD == GET) {
        if (users[ARG] === undefined) return_error('USER DONT EXISTS');
        var user = users[ARG];
        if (OPA === 'name') return_value(user.name);

    }

    if (CMD == OUT) {
        if (users[ARG] === undefined) return_error('USER DONT EXISTS');
        var user = users[ARG];
        output('name', ARG);
        // .. all possible fields
        output('added_by_username', user.added_by_username);

        // ...
        exit();
    }
}



return_error("EXIT on data.js EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);