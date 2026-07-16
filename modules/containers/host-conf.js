#!/bin/node

/*srvctl */

/*
 *   containers/host-conf.js — cluster -> host.conf bootstrap.
 *
 *   Invoked inline by core init.sh (NOT via module hooks — it runs even
 *   when the containers module is disabled) on every root host invocation
 *   when the canonical cluster file exists. Reads /etc/srvctl/clusters.json,
 *   locates the cluster
 *   containing this HOSTNAME, and writes:
 *     - /var/srvctl3/host/host.conf  — SC_HOSTNAME, SC_CLUSTERNAME plus an
 *       SC_<KEY>=<value> line for every scalar key of this host's record
 *       (sourced by init.sh as shell config)
 *     - /var/srvctl3/host/hosts.json — this cluster's host map (consumed by
 *       module-condition.sh and the datastore)
 *
 *   Exit 113 (DATA-ERROR) on validation/read/write failure is a contract with
 *   init.sh. The local hostname must occur exactly once in the canonical
 *   topology; unknown or duplicate placement fails without replacing outputs.
 */

// includes
const fs = require('fs');
const os = require('os');
const path = require('path');
const clusterConfig = require('./lib/cluster-config.js');

// Optional positional paths support isolated selftests. The final optional
// hostname is also used by the validated first-install path: it renders the
// future host projection before update-install persists that hostname and
// requests a reboot. Normal production calls continue to use os.hostname().
const SC_CLUSTERS_FILE = process.argv[2] || "/etc/srvctl/clusters.json";
const SC_HOST_CONF = process.argv[3] || "/var/srvctl3/host/host.conf";
const SC_HOSTS_FILE = process.argv[4] || "/var/srvctl3/host/hosts.json";
const TARGET_HOSTNAME = process.argv[5] || os.hostname();

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exit(113);
}

// Stage every complete output beside its destination. Both files are fully
// written before either rename, and each rename is atomic on the destination
// filesystem. This prevents readers from observing a truncated shell/JSON
// file if the process is interrupted while generating it.
function stageWrite(filename, content) {
    const temporary = filename + '.tmp.' + process.pid + '.' +
        Math.random().toString(16).slice(2);
    fs.writeFileSync(temporary, content, {
        encoding: 'utf8',
        mode: 0o644,
        flag: 'wx'
    });
    return temporary;
}

var projection;
try {
    projection = clusterConfig.buildProjection(
        clusterConfig.readClusters(SC_CLUSTERS_FILE), TARGET_HOSTNAME);
} catch (err) {
    return_error('CLUSTER-CONFIG ' + SC_CLUSTERS_FILE + ' ' + err.message);
}

var hostConfTemporary;
var hostsTemporary;
try {
    fs.mkdirSync(path.dirname(SC_HOST_CONF), { recursive: true, mode: 0o755 });
    fs.mkdirSync(path.dirname(SC_HOSTS_FILE), { recursive: true, mode: 0o755 });
    hostConfTemporary = stageWrite(SC_HOST_CONF, projection.hostConfContent);
    hostsTemporary = stageWrite(SC_HOSTS_FILE, projection.hostsContent);
    fs.renameSync(hostConfTemporary, SC_HOST_CONF);
    hostConfTemporary = undefined;
    fs.renameSync(hostsTemporary, SC_HOSTS_FILE);
    hostsTemporary = undefined;
} catch (err) {
    if (hostConfTemporary) {
        try { fs.unlinkSync(hostConfTemporary); } catch (_) { /* best effort */ }
    }
    if (hostsTemporary) {
        try { fs.unlinkSync(hostsTemporary); } catch (_) { /* best effort */ }
    }
    return_error('WRITEFILES ' + SC_HOST_CONF + ' ' + SC_HOSTS_FILE + ' ' + err);
}
