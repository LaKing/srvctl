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
 *     container) — cluster automation (rsync-over-ssh, backup, gluster)
 *     relies on these for non-interactive ssh;
 *   - scan_host_keys(): ssh-keyscans every cluster host and container
 *     that has no host_key yet, persisting results into hosts.json /
 *     containers.json (read back by datastore lib.js) and the
 *     per-container /srv/<C>/host_key cache file;
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
// opendkim leftovers TrustedHosts/SigningTable/KeyTable); only msg, fs,
// datastore, execSync, os and the SC_* paths are actually used.

function out(msg) {
    console.log(msg);
}

// includes
const fs = require("fs");
const datastore = require("../datastore/lib.js");
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

// Collects a host_key for every cluster host and container that lacks
// one, then rewrites hosts.json / containers.json when anything changed.
function scan_host_keys() {
    msg("Check ssh host_keys");
    let write_hosts = false;
    Object.keys(hosts).forEach(function (i) {
        if (check_host_keys(hosts, i)) write_hosts = true;
    });
    if (write_hosts) fs.writeFileSync(SC_HOSTS_DATA_FILE, JSON.stringify(hosts, null, 2));

    let write_containers = false;
    Object.keys(containers).forEach(function (i) {
        if (check_container_host_keys(containers, i)) write_containers = true;
    });
    if (write_containers) fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
}

// Returns true when containers.json needs a rewrite for container i.
// FIXME(v4): medium — /srv/<C>/host_key is a self-written cache never
// revalidated against the container's real sshd key; a rebuilt
// container keeps its stale key in both known_hosts files forever
// (mitigated for containers by StrictHostKeyChecking no).
function check_container_host_keys(data, i) {
    let path = "/srv/" + i + "/host_key";

    if (data[i].host_key) {
        if (fs.existsSync(path)) if (data[i].host_key === fs.readFileSync(path, "UTF8")) return false;
        msg("check host_key for " + i);
        delete data[i].host_key;
    }

    if (data[i].host_key === undefined) {
        try {
            msg("ssh-keyscan -t rsa -T 1 " + i + " 2> /dev/null");
            var result = execSync("ssh-keyscan -t rsa -T 1 " + i + " 2> /dev/null");
            // FIXME(v4): medium — ssh-keyscan exits 0 even with no output
            // (container down/unreachable), so split(" ")[2] is undefined and
            // writeFileSync(path, undefined) throws: the catch below dumps a
            // stack trace on every regenerate for every stopped container.
            data[i].host_key = result.toString().slice(0, -1).split(" ")[2];
            fs.writeFileSync(path, data[i].host_key);
        } catch (err) {
            if (err) console.log(err);
            if (err) return false;
        }
        return true;
    }
}

// Returns true when hosts.json needs a rewrite for host i.
function check_host_keys(data, i) {
    if (data[i].host_key === undefined) {
        try {
            msg("ssh-keyscan -t rsa -T 1 " + i + " 2> /dev/null");
            var result = execSync("ssh-keyscan -t rsa -T 1 " + i + " 2> /dev/null");
            // FIXME(v4): medium — on a down/unreachable host ssh-keyscan still
            // exits 0 with no output, so host_key is stored as undefined and
            // true is returned, forcing a pointless hosts.json rewrite on
            // every run.
            data[i].host_key = result.toString().slice(0, -1).split(" ")[2];
        } catch (err) {
            if (err) console.log(err);
            if (err) return false;
        }
        return true;
    }
}

// Renders the collected host_keys into the two known_hosts files.
// Line formats (FQDN, host_ip, short hostname and the 10.15.x.x VPN
// alias) are relied on by cluster ssh automation.
function make_host_keys() {
    var keys = "## " + SRVCTL + " generated" + br;

    // FIXME(v4): low — host_ip / hostnet are used unguarded; missing fields
    // yield literal 'undefined ssh-rsa ...' / '10.15.undefined.undefined ...'
    // lines in both known_hosts files.
    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].host_key !== undefined) {
            keys += i + " ssh-rsa " + hosts[i].host_key + br;
            keys += hosts[i].host_ip + " ssh-rsa " + hosts[i].host_key + br;
            keys += i.split(".")[0] + " ssh-rsa " + hosts[i].host_key + br;
            keys += "10.15." + hosts[i].hostnet + "." + hosts[i].hostnet + " ssh-rsa " + hosts[i].host_key + br;
            keys += br;
        }
    });
    Object.keys(containers).forEach(function (i) {
        if (containers[i].host_key !== undefined) {
            keys += i + " ssh-rsa " + containers[i].host_key + br;
            keys += containers[i].ip + " ssh-rsa " + containers[i].host_key + br + br;
        }
    });

    fs.writeFile("/var/srvctl3/share/common/known_hosts", keys, function (err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("ssh share/common/known_hosts");
    });

    // in addition, localhost — appended only to the host-side file: the
    // share/common write above already captured the string by value.
    if (hosts[HOSTNAME])
        if (hosts[HOSTNAME].host_key !== undefined) {
            keys += "localhost ssh-rsa " + hosts[HOSTNAME].host_key + br;
            keys += "127.0.0.1 ssh-rsa " + hosts[HOSTNAME].host_key + br;
        }

    fs.writeFile("/var/srvctl3/ssh/known_hosts", keys, function (err) {
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
