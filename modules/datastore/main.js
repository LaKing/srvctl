#!/bin/node

/*srvctl */

/*
 *  modules/datastore/main.js — the datastore CLI dispatcher.
 *
 *  Invoked as:  /bin/node main.js <cmd> <dat> <arg> [opa] [val]
 *  by the bash verb wrappers in libs/bashlib.sh, where
 *    cmd = get | put | out | cfg | del | new | add
 *    dat = cluster | user | reseller | container | host
 *  Reads and writes the json files under $SC_DATASTORE_DIR through lib.js.
 *
 *  Exit-code contract (parsed by bashlib.sh — do not change):
 *    0    value returned / operation done
 *    100  requested optional value is not defined (empty get)
 *    110  MAIN-ERROR printed on stderr (bad arguments, missing record)
 *    112  LIB-ERROR raised inside lib.js
 *    99   fell through without matching any command
 *
 *  Output formats (captured/sourced by callers — do not change):
 *    get: the bare value.  out: VAR='value' lines, "-" replaced by "_" in
 *    names, object values JSON.stringify'd; "out container X json" prints
 *    pretty JSON with 4-space indent; "out host X" prefixes keys with SC_.
 *
 *  Scheduled for a full .mjs rewrite in v4; this pass is comments only.
 */

function log(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

// implement a very simple human-readable command set for data manipulation
// for example.: [sc] get container hangmaffia-devel users

// command: get put, ...
const CMD = process.argv[2];
// database: users, containers, cluster, ..
const DAT = process.argv[3];
// database defining argument
const ARG = process.argv[4];
// operand / optional argument
const OPA = process.argv[5];
// value
const VAL = process.argv[6];

// constants

// FIXME(v4): SC_HOSTS_DATA_FILE, SC_USERS_DATA_FILE, SC_CONTAINERS_DATA_FILE,
// SC_DATASTORE_RO and SC_RESELLER_USER are unused in this file (lib.js reads
// its own copies) — dead constants; drop them in the mjs rewrite.
const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/hosts.json";

const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/users.json";
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const SC_RESELLER_USER = process.env.SC_RESELLER_USER;

// FIXME(v4): SC_USER is an implicit global (no var/const/let declaration);
// would throw a ReferenceError under strict mode / ES modules.
if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

const PUT = "put";
const GET = "get";
const OUT = "out";
const CFG = "cfg";
const DEL = "del";
const NEW = "new";
const ADD = "add";
// fix is actually unused

const dot = ".";
const root = "root";
// netblock size
const NBC = 16;

process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error("MAIN-ERROR:", msg);
    process.exitCode = 110;
    process.exit(110);
}

function output(variable, value) {
    if (typeof value === "object") value = JSON.stringify(value);
    console.log(variable.replace(/-/g, "_") + "='" + value + "'");
    process.exitCode = 0;
}

function output_json(value) {
    console.log(JSON.stringify(value, null, 4));
    process.exitCode = 0;
}

// 1. get or put
if (CMD === undefined) return_error("MISSING CMD ARGUMENT: get | put | out | cfg | del | new | add");
// 2. users or containers
if (DAT === undefined) return_error("MISSING DAT ARGUMENT: cluster | user | reseller | container | host");
// 3. field
if (ARG === undefined) return_error("MISSING ARG ARGUMENT: containername / username / hostname / query");
// 4. OPA is optional

if (CMD !== GET && CMD !== PUT && CMD !== OUT && CMD !== CFG && CMD !== DEL && CMD !== NEW && CMD !== ADD) return_error("INVALID CMD ARGUMENT: " + CMD);
if (DAT !== "cluster" && DAT !== "user" && DAT != "container" && DAT != "host" && DAT != "reseller") return_error("INVALID DAT ARGUMENT: " + DAT);

// variables
var user = "";
var container = "";

var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;

if (DAT === "container") {
    if (CMD === NEW) {
        datastore.new_container(ARG, OPA, VAL);
        exit();
    }

    if (CMD === GET && OPA === "exist") {
        if (containers[ARG] !== undefined) return_value("true");
        else return_value("false");
    } else {
        if (containers[ARG] === undefined) return_error("CONTAINER " + ARG + " DONT EXISTS");
        else {
            // container must exist
            var container = containers[ARG];
            const C = ARG;

            if (CMD === PUT) {
                if (VAL === undefined) delete containers[ARG][OPA];
                else if (VAL === "true") containers[ARG][OPA] = true;
                else if (VAL === "false") containers[ARG][OPA] = false;
                else containers[ARG][OPA] = VAL;
                datastore.write_containers();
                exit();
            }

            if (CMD === CFG) {
                if (OPA === "update_ip") return_value(datastore.container_update_ip(C));
                else if (OPA === "add_mapped_port") return_value(datastore.container_add_mapped_port(C));
                else return_error("INTERNAL CFG FUNCTION DONT EXISTS");

                exit();
            }

            if (CMD == OUT) {
                if (OPA === "json") {
                	 output_json(container);
                     return exit();
                }
                output("C", ARG);
                Object.keys(container).forEach(function(j) {
                    output(j, container[j]);
                });
                exit();
            }

            if (CMD === DEL) {
                delete containers[ARG];
                datastore.write_containers();
                exit();
            }
            // FIXME(v4): duplicate ADD blocks — for `add container X vncuser Y`
            // this first block calls write_containers() BEFORE the vncuser is
            // pushed (persisting a stale file), then the second block pushes
            // and writes again: two racing async fs.writeFile calls on
            // containers.json, and exit()/write_containers() run twice per
            // ADD. Merge into a single block with one write in the rewrite.
            if (CMD === ADD) {
                if (OPA === 'user' && VAL) {
                	if (!container.users) container.users = [];
                  	if (container.users.indexOf(VAL) < 0) container.users.push(VAL);
                  	return_value(container.users);
                }
                datastore.write_containers();
                exit();
            }
            if (CMD === ADD) {
                if (OPA === 'vncuser' && VAL) {
                	if (!container.vncusers) container.vncusers = [];
                  	if (container.vncusers.indexOf(VAL) < 0) container.vncusers.push(VAL);
                  	return_value(container.vncusers);
                }
                datastore.write_containers();
                exit();
            }
            // GET single values
            if (CMD === GET) {
                const fn = "container_" + OPA;
                if (datastore[fn]) {
                    return_value(datastore[fn](C));
                } else return_value(container[OPA]);
            }
        }
    }
}

if (DAT === "user") {
    if (CMD === NEW) {
        datastore.new_user(ARG);
        exit();
    } else if (CMD === GET && OPA === "exist") {
        if (users[ARG] !== undefined) return_value("true");
        else return_value("false");
    } else if (CMD === CFG && ARG === "container_list") {
        return_value(datastore.user_container_list(SC_USER));
    } else {
        if (users[ARG] === undefined) return_error("USER DONT EXISTS");
        else {
            var user = users[ARG];
            const U = ARG;

            if (CMD === PUT) {
                if (VAL === undefined) delete users[U][OPA];
                else if (VAL === "true") users[U][OPA] = true;
                else if (VAL === "false") users[U][OPA] = false;
                else users[U][OPA] = VAL;
                datastore.write_users();
                exit();
            }

            if (CMD == OUT) {
                output("U", ARG);
                var user = users[ARG];
                Object.keys(user).forEach(function(j) {
                    output(j, user[j]);
                });
                exit();
            }

            if (CMD === DEL) {
                delete users[ARG];
                datastore.write_users();
                exit();
            }

            // GET
            if (CMD === GET) {
                const fn = "user_" + OPA;
                if (datastore[fn]) return_value(datastore[fn](U));
                else return_value(users[U][OPA]);
            }
        }
    }
}

if (DAT === "reseller") {
    if (CMD === NEW) {
        datastore.new_reseller(ARG);
        exit();
    }
}

if (DAT === "host") {
    if (hosts[ARG] === undefined) return_error("HOST " + ARG + " DONT EXISTS " + JSON.stringify(Object.keys(hosts)));
    else {
                
        var host = hosts[ARG];        
        
        if (CMD === GET) {
            return_value(host[OPA]);
        }

        if (CMD == OUT) {
            output("SC_HOSTNAME", ARG);
            Object.keys(host).forEach(function(j) {
                output("SC_" + j.toUpperCase(), host[j]);
            });
            exit();
        }
    }
}

if (DAT === "cluster") {
    if (CMD === GET) {
        const fn = "cluster_" + ARG;
        if (datastore[fn]) return_value(datastore[fn]());
    }
}

// no match above leaves the default process.exitCode = 99
