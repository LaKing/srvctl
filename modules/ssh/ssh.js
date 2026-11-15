#!/bin/node

/*
 * modules/ssh/ssh.js — ssh config, known_hosts and user-key generator.
 *
 * Run as root by ssh_main (libs/sshlib.sh) on every regenerate and on
 * update-install-host. argv is read into CMD but never used: every
 * invocation performs all four steps, in order:
 *   - ssh_config(): writes the client drop-ins
 *     /etc/ssh/ssh_config.d/srvctl-chosts.conf (cluster hosts, FQDN and
 *     short-name blocks pointing at /var/srvctl3/ssh/known_hosts) and
 *     srvctl-containers.conf (root login, StrictHostKeyChecking no per
 *     container) — cluster automation (rsync-over-ssh, backup)
 *     relies on these for non-interactive ssh;
 *   - scan_host_keys(): ssh-keyscans (RSA) every cluster host that has
 *     no host_key yet and revalidates every local running container
 *     against its sshd (lib/hostkeys.js has the full policy), persisting
 *     new or changed keys into the hosts / containers datastore records
 *     and the per-container /srv/<C>/host_key cache file; key changes
 *     are logged with old/new SHA256 fingerprints (console + $SC_LOG);
 *     empty or failed scans keep the existing key;
 *   - make_host_keys(): renders the collected keys into
 *     /var/srvctl3/share/common/known_hosts (bind-mounted RO into
 *     containers) and /var/srvctl3/ssh/known_hosts (host side, with two
 *     extra localhost entries);
 *   - user_keys(): copies each container user's datastore .pub/.hash
 *     files to /var/srvctl3/share/containers/<C>/users/<U>/<U>-<file> —
 *     consumed by sshd_authorization.sh (AuthorizedKeysCommand) and by
 *     codepad's access.js.
 * A write failure exits 111 with a DATA-ERROR: line, aborting the whole
 * srvctl run via ssh_main's exif; success exits 0.
 */

/*srvctl */

// FIXME(v4): most of the shared datastore-js boilerplate below is dead
// in this script (out, ntc, err, get, run, rok, exec_function, CMD,
// SC_UID0, localhost, user, container, return_value/output and the
// opendkim leftovers TrustedHosts/SigningTable/KeyTable); only msg, ntc,
// err, fs, datastore, hostkeys, os and the SC_* paths are actually used.

function out(msg) {
    console.log(msg);
}

// includes
const fs = require("fs");
const datastore = require("../datastore/lib.js");
const hostkeys = require("./lib/hostkeys.js");
const execSync = require("child_process").execSync;

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;
const exec_function = require(lablib).exec_function;

const os = require("os");
const HOSTNAME = os.hostname();

const CMD = process.argv[2];
// constants
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/hosts.json";
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;

const localhost = "localhost";
const br = "\n";
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
    console.error("DATA-ERROR:", msg);
    process.exitCode = 111;
    process.exit(111);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
    process.exitCode = 0;
}

// variables
var hosts = datastore.hosts;
var users = datastore.users;
var resellers = datastore.resellers;
var containers = datastore.containers;
var user = "";
var container = "";

// FIXME(v4): dead copy-paste from the opendkim module — never used here.
var TrustedHosts = "";
var SigningTable = "";
var KeyTable = "";

TrustedHosts += "127.0.0.1" + br;
TrustedHosts += "::1" + br;
TrustedHosts += "10.0.0.0/8" + br;

// Copies user u's datastore public keys into the share dir of container
// c, as <u>-<origfile> (naming consumed by sshd_authorization.sh and
// codepad's access.js); the datastore user dir is created on the fly.
// FIXME(v4): high — distribution is add-only: stale copies are never
// removed (regenerate_ssh_config only purges files named
// authorized_keys), so key revocation / user removal never propagates
// to containers.
function copy_user_key(c, u) {
    if (u === "root") return;
    var i;

    // FIXME(v4): low — fs.mkdirSync without {recursive:true} throws
    // (uncaught, killing the whole run) if /var/srvctl3/share/containers
    // itself is missing.
    var dir = "/var/srvctl3/share/containers/" + c;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }

    dir = SC_DATASTORE_DIR + "/users/" + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }

    dir = "/var/srvctl3/share/containers/" + c + "/users";
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    dir = "/var/srvctl3/share/containers/" + c + "/users/" + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }

    var files = fs.readdirSync(SC_DATASTORE_DIR + "/users/" + u);

    var pub;
    for (i = 0; i < files.length; i++) {
        // FIXME(v4): high — split(".")[1] only matches names with exactly one
        // dot; keys added by 'sc add-publickey' (<user>-YYYY.MM.DD-HH:MM:SS.pub)
        // are silently skipped, so those users never get ssh access to their
        // containers. Should be endsWith(".pub") / endsWith(".hash").
        if (files[i].split(".")[1] === "pub" || files[i].split(".")[1] === "hash") {
            const pubfile = SC_DATASTORE_DIR + "/users/" + u + "/" + files[i];
            if (fs.existsSync(pubfile)) {
                pub = fs.readFileSync(pubfile);
                fs.writeFileSync(dir + "/" + u + "-" + files[i], pub);
            }
        }
    }
}

// Distributes keys for everyone entitled to log into container c:
// users tagged access=all, the primary user, the extra users list and
// the primary user's reseller.
function remake_ssh_keys(c) {
    if (containers[c].user === undefined) return;

    //  the users may have a special all-access tag
    Object.keys(users).forEach(function (u) {
        if (users[u].access == "all") copy_user_key(c, u);
    });

    // primary user
    copy_user_key(c, containers[c].user);

    // other users (developers, guests, people that are allowed to have root access)
    if (containers[c].users !== undefined) {
        for (var i = 0; i < containers[c].users.length; i++) {
            copy_user_key(c, containers[c].users[i]);
        }
    }

    // reseller
    if (users[containers[c].user] === undefined) return;
    if (users[containers[c].user].reseller === undefined) return;
    copy_user_key(c, users[containers[c].user].reseller);
}

// FIXME(v4): low — iterates the cluster-wide containers.json, creating
// orphan share dirs on this host for containers hosted on other machines.
function user_keys() {
    Object.keys(containers).forEach(function (c) {
        remake_ssh_keys(c);
    });
}

function ssh_config() {
    var str = "## ssh_config" + br;
    str += "Host localhost" + br;
    str += "User root" + br;
    str += "StrictHostKeyChecking no" + br;
    str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
    str += "" + br;

    str += "Host 127.0.0.1" + br;
    str += "User root" + br;
    str += "StrictHostKeyChecking no" + br;
    str += "" + br;

    Object.keys(hosts).forEach(function (i) {
        str += "Host " + i + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "" + br;

        str += "Host " + i.split(".")[0] + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "" + br;
    });
    fs.writeFile("/etc/ssh/ssh_config.d/srvctl-chosts.conf", str, function (err) {
        if (err) return_error("WRITEFILE " + err);
        // FIXME(v4): low — message says srvctl-hosts.conf but the file
        // written is srvctl-chosts.conf.
        else msg("ssh srvctl-hosts.conf");
    });

    str = "";
    Object.keys(containers).forEach(function (i) {
        str += "Host " + i + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        // FIXME(v4): low — UserKnownHostsFile is set twice; OpenSSH takes
        // the first match per option, so the /dev/null line is dead.
        str += "UserKnownHostsFile /dev/null" + br;

        str += "" + br;
    });
    fs.writeFile("/etc/ssh/ssh_config.d/srvctl-containers.conf", str, function (err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("ssh srvctl-containers.conf");
    });
}

// for known hosts

// Appends a host-key event to $SC_LOG (passed in by ssh_main) and echoes
// it on the console; "changed" events are highlighted.
function log_host_key(text, kind) {
    if (kind === "error") err(text);
    else if (kind === "changed") ntc(text);
    else msg(text);
    if (process.env.SC_LOG) {
        try {
            fs.appendFileSync(process.env.SC_LOG, new Date().toISOString() + ": " + text + br);
        } catch (e) {
            // console output above is the fallback
        }
    }
}

const HOSTKEY_OPTS = { log: log_host_key };

// Collects / revalidates host_keys (policy in lib/hostkeys.js), then
// rewrites the hosts / containers datastore records when anything changed.
function scan_host_keys() {
    msg("Check ssh host_keys");
    let write_hosts = false;
    Object.keys(hosts).forEach(function (i) {
        if (hostkeys.check_host_key(hosts, i, HOSTKEY_OPTS)) write_hosts = true;
    });
    if (write_hosts) datastore.save_type("hosts", hosts); // was monolithic write, lost on v4 per-entity

    let write_containers = false;
    Object.keys(containers).forEach(function (i) {
        if (hostkeys.check_container_host_key(containers, i, HOSTKEY_OPTS)) write_containers = true;
    });
    if (write_containers) datastore.save_type("containers", containers); // was monolithic write, lost on v4 per-entity
}

// Renders the collected host_keys into the two known_hosts files.
function make_host_keys() {
    const known_hosts = hostkeys.render_known_hosts(hosts, containers, SRVCTL, HOSTNAME);

    fs.writeFile("/var/srvctl3/share/common/known_hosts", known_hosts.common, function (err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("ssh share/common/known_hosts");
    });

    // host side additionally carries the localhost entries
    fs.writeFile("/var/srvctl3/ssh/known_hosts", known_hosts.host, function (err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("ssh ssh/known_hosts");
    });
}

ssh_config();

scan_host_keys();
make_host_keys();

user_keys();

process.exitCode = 0;

process.on("exit", function () {
    msg("ssh configuration done");
});

exit();
