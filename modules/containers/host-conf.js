#!/bin/node

/*srvctl */

/*
 *   containers/host-conf.js — cluster -> host.conf bootstrap.
 *
 *   Invoked inline by core init.sh (NOT via module hooks — it runs even
 *   when the containers module is disabled) whenever the cluster data
 *   file exists. Reads /etc/srvctl/clusters.json, locates the cluster
 *   containing this HOSTNAME, and writes:
 *     - /etc/srvctl/host.conf  — SC_HOSTNAME, SC_CLUSTERNAME plus an
 *       SC_<KEY>=<value> line for every scalar key of this host's record
 *       (sourced by init.sh as shell config)
 *     - /etc/srvctl/hosts.json — this cluster's host map (consumed by
 *       module-condition.sh and the datastore)
 *
 *   Exit 113 (DATA-ERROR) on read/write failure is a contract with
 *   init.sh. Note: an unknown HOSTNAME writes an empty hosts.json and a
 *   host.conf without SC_CLUSTERNAME — silently, by design.
 */

// includes
const fs = require('fs');
const os = require('os');

// constants
const HOSTNAME = os.hostname();
const br = '\n';

const SC_HOSTS_DATA_FILE = "/etc/srvctl/hosts.json";
const SC_CLUSTERS_DATA_FILE = "/etc/srvctl/clusters.json";
const SC_HOST_CONF = "/etc/srvctl/host.conf";

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exit(113);
}

var out = '#!/bin/bash' + br;
out += "SC_HOSTNAME=" + HOSTNAME + br;

var clusters;
try {
    clusters = JSON.parse(fs.readFileSync(SC_CLUSTERS_DATA_FILE));
} catch (err) {
    return_error('READFILE ' + SC_CLUSTERS_DATA_FILE + ' ' + err);
}

var hosts = {};
Object.keys(clusters).forEach(function(i) {
    Object.keys(clusters[i]).forEach(function(j) {
        if (j === HOSTNAME) {
            out += "SC_CLUSTERNAME=" + i + br;
            hosts = clusters[i];
        }
    });
});

if (hosts[HOSTNAME])
Object.keys(hosts[HOSTNAME]).forEach(function(j) {
    if (typeof hosts[HOSTNAME][j] === 'string' || typeof hosts[HOSTNAME][j] === 'number' || typeof hosts[HOSTNAME][j] === 'boolean')
        out += 'SC_' + j.toUpperCase() + '=' + hosts[HOSTNAME][j] + br;
});

try {
    fs.writeFileSync(SC_HOST_CONF, out);
} catch (err) {
    return_error('WRITEFILE ' + SC_HOST_CONF + ' ' + err);
}

try {
    fs.writeFileSync(SC_HOSTS_DATA_FILE, JSON.stringify(hosts, null, 2));
} catch (err) {
    return_error('WRITEFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
}
