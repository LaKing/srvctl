#!/bin/node

/*srvctl */

// PROCESS user.conf
//
// modules/usersonhost/user.js — writes ~/.srvctl/user.conf: a sourceable
// bash file with one SC_USER_<KEY>=<value> line per scalar property of
// users.json[SC_USER]. Only invoked via the usercfg wrapper in
// libs/bashlib.sh.
//
// FIXME(v4): dead code — usercfg (and therefore this script) has no
// caller anywhere in the tree; delete or wire up in v4.

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

// FIXME(v4): unused constant, and it aliases SC_DATASTORE_DIR to the
// unrelated SC_DATASTORE_RO flag — remove.
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_RO;
const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/users.json';
const SC_USER_CONF = SC_HOME + '/.srvctl/user.conf';

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exit(111);
}

var out = '#!/bin/bash' + br;

// Read users in EITHER layout (v4 per-entity users/<id>.json, or v3 monolithic
// users.json): monolithic base, per-entity wins, marker => per-entity
// authoritative. A migrated store has no users.json (ENOENT is not an error) —
// without this the command crashed with LIB-ERROR: READFILE on a v4 host.
var users = (function () {
    var dir = process.env.SC_DATASTORE_DIR;
    var result = {};
    if (!fs.existsSync(dir + '/.per-entity')) {
        try {
            var mono = JSON.parse(fs.readFileSync(dir + '/users.json'));
            if (mono && typeof mono === 'object' && !Array.isArray(mono)) Object.keys(mono).forEach(function (id) { result[id] = mono[id]; });
        } catch (e) { if (e.code !== 'ENOENT') return_error('READFILE ' + dir + '/users.json ' + e); }
    }
    try {
        fs.readdirSync(dir + '/users').forEach(function (n) {
            if (n.slice(-5) !== '.json' || n.charAt(0) === '.') return;
            result[n.slice(0, -5)] = JSON.parse(fs.readFileSync(dir + '/users/' + n));
        });
    } catch (e) { if (e.code !== 'ENOENT') return_error('READDIR ' + dir + '/users ' + e); }
    return result;
})();

// FIXME(v4): throws (uncaught TypeError, exit 1 instead of the 111
// convention) when SC_USER is not present in users.json.
// FIXME(v4): values are written unquoted, so a value containing spaces
// or shell metacharacters breaks the sourcing side (usercfg).
Object.keys(users[SC_USER]).forEach(function(j) {
    if (typeof users[SC_USER][j] === 'string' || typeof users[SC_USER][j] === 'number' || typeof users[SC_USER][j] === 'boolean')
    out += 'SC_USER_' + j.toUpperCase() + '=' + users[SC_USER][j] + br;
});

try {
    fs.writeFileSync(SC_USER_CONF, out);
} catch (err) {
        return_error('WRITEFILEFILE ' + SC_USER_CONF + ' ' + err + ' (usersonhost)');
}

