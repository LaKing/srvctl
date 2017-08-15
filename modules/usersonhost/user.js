#!/bin/node

/*jshint esnext: true */

// PROCESS user.conf

// includes
const fs = require('fs');
const os =  require('os');

// constants
const HOSTNAME = os.hostname();
const br = '\n';

var user;
if (process.env.SC_USER !== undefined) user = process.env.SC_USER;
else user = process.env.USER;
var home;
if (process.env.SC_HOME !== undefined) home = process.env.SC_HOME;
else home = '/home/' + user;

const SC_USER = user;
const SC_HOME = home;

const SC_DATASTORE_DIR = process.env.SC_DATASTORE_RO;
const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/users.json';
const SC_USER_CONF = SC_HOME + '/.srvctl/user.conf';

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exit(111);
}

var out = '#!/bin/bash' + br;

var users;
try {
    users = JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
} catch (err) {
        return_error('READFILE ' + SC_USERS_DATA_FILE + ' ' + err);
}

Object.keys(users[SC_USER]).forEach(function(j) {
    if (typeof users[SC_USER][j] === 'string' || typeof users[SC_USER][j] === 'number' || typeof users[SC_USER][j] === 'boolean')
    out += 'SC_USER_' + j.toUpperCase() + '=' + users[SC_USER][j] + br;
});

try {
    fs.writeFileSync(SC_USER_CONF, out);
} catch (err) {
        return_error('WRITEFILEFILE ' + SC_USER_CONF + ' ' + err);
}

