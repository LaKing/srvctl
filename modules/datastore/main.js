#!/bin/node

/*srvctl */

function log(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

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

// constatnts

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/hosts.json";

const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/users.json";
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const SC_RESELLER_USER = process.env.SC_RESELLER_USER;

if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

const PUT = "put";
const GET = "get";
const OUT = "out";
const CFG = "cfg";
const DEL = "del";
const NEW = "new";
const FIX = "fix";
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
    console.log(JSON.stringify(value));
    process.exitCode = 0;
}

// 1. get or put
if (CMD === undefined) return_error("MISSING CMD ARGUMENT: get | put | out | cfg | del | new | fix");
// 2. users or containers
if (DAT === undefined) return_error("MISSING DAT ARGUMENT: cluster | user | reseller | container | host");
// 3. field
if (ARG === undefined) return_error("MISSING ARG ARGUMENT: containername / username / hostname / query");
// 4. OPA is optional

if (CMD !== GET && CMD !== PUT && CMD !== OUT && CMD !== CFG && CMD !== DEL && CMD !== NEW && CMD !== FIX) return_error("INVALID CMD ARGUMENT: " + CMD);
if (DAT !== "cluster" && DAT !== "user" && DAT != "container" && DAT != "host" && DAT != "reseller") return_error("INVALID DAT ARGUMENT: " + DAT);

// variables
var user = "";
var container = "";

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

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
            /*
          	// get single values
            if (CMD === GET) {
                if (OPA === "interface") return_value(datastore.container_interface(C));
                else if (OPA === "bridge") return_value(datastore.container_bridge(C));
                else if (OPA === "br") return_value(datastore.container_br(C));
                else if (OPA === "gw") return_value(datastore.container_gw(C));
                else if (OPA === "br_host_ip") return_value(datastore.container_br_host_ip(C));
                else if (OPA === "reseller") return_value(datastore.container_reseller(C));
                else if (OPA === "host_ip") return_value(datastore.container_host_ip(C));
                else if (OPA === "host") return_value(datastore.container_host(C));
                else if (OPA === "http_port") return_value(datastore.container_http_port(C));
                else if (OPA === "https_port") return_value(datastore.container_https_port(C));
                else if (OPA === "uid") return_value(datastore.container_uid(C));
                else if (OPA === "user_id") return_value(datastore.container_user_id(C));
                else if (OPA === "user_ip_match") return_value(datastore.container_user_ip_match(C));
                else if (OPA === "mx") return_value(datastore.container_mx(C));
                else if (OPA === "resolv_conf") return_value(datastore.container_resolv_conf(C));
                else if (OPA === "br_netdev") return_value(datastore.container_br_netdev(C));
                else if (OPA === "br_network") return_value(datastore.container_br_network(C));
                else if (OPA === "hosts") return_value(datastore.container_hosts(C));
                else if (OPA === "nspawn") return_value(datastore.container_nspawn(C));
                else if (OPA === "ethernet") return_value(datastore.container_ethernet(C));
                else if (OPA === "ethernet_network") return_value(datastore.container_ethernet_network(C));
                else if (OPA === "firewall_commands") return_value(datastore.container_firewall_commands(C));
                else return_value(container[OPA]);
            }*/

            if (CMD === CFG) {
                if (OPA === "update_ip") return_value(datastore.container_update_ip(C));
                else if (OPA === "add_mapped_port") return_value(datastore.container_add_mapped_port(C));
                else return_error("INTERNAL CFG FUNCTION DONT EXISTS");

                exit();
            }

            if (CMD == OUT) {
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

            // GET
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

//return_error("EXIT on data.js EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);
