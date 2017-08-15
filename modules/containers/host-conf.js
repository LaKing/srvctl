#!/bin/node

/*jshint esnext: true */

// includes
const fs = require('fs');
const os = require('os');

// constants
const HOSTNAME = os.hostname();
const br = '\n';

const SC_HOSTS_DATA_FILE = "/etc/srvctl/hosts.json";
const SC_CLUSTERS_DATA_FILE = "/etc/srvctl/data/clusters.json";
const SC_HOST_CONF = "/etc/srvctl/host.conf";

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exit(111);
}

var out = '#!/bin/bash' + br;
out += "SC_HOSTNAME=" + HOSTNAME + br;

var clusters;
try {
    clusters = JSON.parse(fs.readFileSync(SC_CLUSTERS_DATA_FILE));
} catch (err) {
    return_error('READFILE ' + SC_CLUSTERS_DATA_FILE + ' ' + err);
}

var hosts;
Object.keys(clusters).forEach(function(i) {
    Object.keys(clusters[i]).forEach(function(j) {
        if (j === HOSTNAME) out += "SC_CLUSTERNAME=" + i + br;
        hosts = clusters[i];
    });
});

Object.keys(hosts[HOSTNAME]).forEach(function(j) {
    if (typeof hosts[HOSTNAME][j] === 'string' || typeof hosts[HOSTNAME][j] === 'number' || typeof hosts[HOSTNAME][j] === 'boolean')
        out += 'SC_' + j.toUpperCase() + '=' + hosts[HOSTNAME][j] + br;
});

try {
    fs.writeFileSync(SC_HOST_CONF, out);
} catch (err) {
    return_error('WRITEFILEFILE ' + SC_HOST_CONF + ' ' + err);
}

try {
    fs.writeFileSync(SC_HOSTS_DATA_FILE, JSON.stringify(hosts, null, 2));
} catch (err) {
    return_error('WRITEFILEFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
}
