#!/bin/node

/*srvctl */

function log(msg) {
    console.log(msg);
}

// includes
var fs = require("fs");
var datastore = require("../datastore/lib.js");

const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];
const VAL = process.argv[6];

// constatnts

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/hosts.json";

const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/users.json";
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const SC_RESELLER_USER = process.env.SC_RESELLER_USER;

const PUT = "put";
const GET = "get";
const OUT = "out";
const CFG = "cfg";
const DEL = "del";
const NEW = "new";
const FIX = "fix";
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
    console.error("DATA-ERROR:", msg, process.argv);
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
        datastore.new_container(ARG, OPA);
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

            if (CMD === GET) {
                if (OPA === "interface") return_value(datastore.container_interface_name(container));
                else if (OPA === "br") return_value(datastore.container_br(container));
                else if (OPA === "gw") return_value(datastore.container_gw(container));
                else if (OPA === "br_host_ip") return_value(datastore.container_bridge_host_ip(container));
                else if (OPA === "reseller") return_value(datastore.container_reseller_user(container));
                else if (OPA === "host_ip") return_value(datastore.container_host_ip(container));
                else if (OPA === "host") return_value(datastore.container_host(container));
                else if (OPA === "http_port") return_value(datastore.container_http_port(container));
                else if (OPA === "https_port") return_value(datastore.container_https_port(container));
                else if (OPA === "uid") return_value(datastore.container_uid(container));
                else if (OPA === "user_id") return_value(datastore.container_user_id(container));
                else if (OPA === "user_ip_match") return_value(datastore.container_check_user_ip_match(container));
                else if (OPA === "mx") return_value(datastore.container_mx(C));
                else return_value(container[OPA]);
            }

            if (CMD === CFG) {
                if (OPA === "resolv_conf") return_value(datastore.container_resolv_conf(container));
                else if (OPA === "br_netdev") return_value(datastore.container_br_netdev(container));
                else if (OPA === "br_network") return_value(datastore.container_br_network(container));
                else if (OPA === "hosts") return_value(datastore.container_hosts(C));
                else if (OPA === "nspawn") return_value(datastore.container_nspawn(C));
                else if (OPA === "container_firewall_commands") return_value(datastore.container_firewall_commands(container, C));
                else return_value(JSON.stringify(container, null, 4));
            }

            if (CMD === FIX) {
                if (OPA === "update_container_ip") return_value(datastore.update_container_ip(C));
                else return_error("INTERNAL FUNCTION DONT EXISTS");

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
        }
    }
}

if (DAT === "user") {
    if (CMD === NEW) {
        datastore.new_user(ARG);
        exit();
    } else if (CMD === CFG) {
        if (ARG === "container_list") return_value(datastore.user_container_list());
    } else if (CMD === GET && OPA === "exist") {
        if (users[ARG] !== undefined) return_value("true");
        else return_value("false");
    } else {
        if (users[ARG] === undefined) return_error("USER DONT EXISTS");
        else {
            if (CMD === PUT) {
                if (VAL === undefined) delete containers[ARG][OPA];
                else if (VAL === "true") containers[ARG][OPA] = true;
                else if (VAL === "false") containers[ARG][OPA] = false;
                else containers[ARG][OPA] = VAL;
                datastore.write_users();
                exit();
            }

            if (CMD === GET) {
                if (OPA === "br_host_ip") return_value(datastore.get_user_uid(user));
                //else
                return_value(users[ARG][OPA]);
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
    if (CMD === CFG) {
        if (ARG === "etc_hosts") datastore.cluster_etc_hosts();
        if (ARG === "postfix_relaydomains") datastore.cluster_postfix_relaydomains();
        if (ARG === "host_keys") datastore.cluster_host_keys();
        if (ARG === "container_list") return_value(datastore.cluster_container_list());
        if (ARG === "host_list") return_value(datastore.cluster_host_list());
        if (ARG === "host_ip_list") return_value(datastore.cluster_host_ip_list());
        if (ARG === "user_list") return_value(datastore.cluster_user_list());
        exit();
    }
}

//return_error("EXIT on data.js EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);
