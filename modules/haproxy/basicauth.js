/*
   haproxy/basicauth.js — basic auth of containers in haproxy.

   The container key 'basicauth' ("all" or "443,9000", set by
   commands/basicauth-ve-port.sh) says which ports are protected. It holds no
   secret, so it may live in the public container record. The credentials are
   the srvctl users' own login passwords: every user with access to the
   container, read from $SC_DATASTORE_DIR/users/<u>/.password (root-only, the
   source usersonhost/main.js syncs to passwd and ~/.password). The ~/.password
   copy is not read: the user owns the home directory and could replace it.

   Used by haproxy.js (render) and by the command (node basicauth.js missing VE).
   CommonJS because haproxy.js requires it synchronously.
*/

const fs = require("fs");
const path = require("path");

// The ports haproxy.js renders a per-container backend for. 80/443 map to the
// http:<ve>/https:<ve> backends, the rest to port<N>:<ve>.
const PORTS = [80, 443, 8080, 8443, 9000, 9001, 9002, 9200];

// parse_ports VALUE: "all" or a sorted port array. A hand-edited bad value throws:
// rendering stops and haproxy keeps its previous config instead of dropping the protection.
function parse_ports(c, v) {
    if (v === "all") return "all";
    const ports = String(v).split(",").map(Number);
    if (!ports.every((n) => PORTS.includes(n))) throw new Error("container " + c + ": invalid basicauth value " + JSON.stringify(v));
    return ports.sort((a, b) => a - b);
}

// access_users: who may enter container c. Same set as codepad/access.js, which
// publishes the codepad login credentials: users with access "all", the owner,
// the container's users[] and the owner's reseller; never root. readers[] (the
// read-only file mounts) are not included, as in codepad.
function access_users(containers, users, c) {
    const set = new Set();
    for (const u of Object.keys(users)) if (users[u].access === "all") set.add(u);
    const owner = containers[c].user;
    if (owner !== undefined) set.add(owner);
    for (const u of containers[c].users || []) set.add(u);
    if (owner !== undefined && users[owner] && users[owner].reseller !== undefined) set.add(users[owner].reseller);
    set.delete("root");
    return [...set].sort();
}

function read_password(datastore_dir, u) {
    try {
        return fs.readFileSync(path.join(datastore_dir, "users", u, ".password"), "utf8").trim();
    } catch (err) {
        if (err.code === "ENOENT") return null;
        throw err;
    }
}

// build: { <ve>: { ports, users: { <u>: <password> } } } for every protected
// container. A user without a usable password is left out and reported: that
// locks the user out, it never opens the site. The value goes into haproxy.cfg
// verbatim, hence the character check (password/lib.js generates [A-Za-z-]).
function build(containers, users, datastore_dir, warn) {
    const out = {};
    for (const c of Object.keys(containers)) {
        if (containers[c].basicauth === undefined) continue;
        const entry = { ports: parse_ports(c, containers[c].basicauth), users: {} };
        for (const u of access_users(containers, users, c)) {
            const pw = read_password(datastore_dir, u);
            if (pw === null) warn("basicauth " + c + ": " + u + " has no .password, left out");
            else if (!/^[A-Za-z0-9._-]+$/.test(u) || !/^[A-Za-z0-9._-]+$/.test(pw)) warn("basicauth " + c + ": " + u + " has a name or password haproxy cannot take, left out");
            else entry.users[u] = pw;
        }
        if (Object.keys(entry.users).length === 0) warn("basicauth " + c + ": no user can log in");
        out[c] = entry;
    }
    return out;
}

function covers(e, n) {
    return e !== undefined && (e.ports === "all" || e.ports.includes(n));
}

// userlists: one userlist per protected container.
// insecure-password, not a crypt hash: haproxy would run crypt() on every request.
// The passwords are host login passwords, so haproxy.js writes the cfg 0600.
function userlists(auth) {
    let str = "";
    for (const c of Object.keys(auth)) {
        str += "\nuserlist basicauth:" + c;
        for (const u of Object.keys(auth[c].users)) str += "\n    user " + u + " insecure-password " + auth[c].users[u];
        str += "\n";
    }
    return str;
}

// rule: the auth lines for backend <proto>:<c> on port n, or "". Placed in the
// backend, so every frontend ACL (names, aliases, altnames, subdomains) hits it,
// while /.well-known goes to its own backends and ACME keeps working.
// X-Robots-Tag via http-after-response, not http-response: only the former also
// covers the 401 haproxy generates itself, so even the login page is not indexed.
function rule(auth, c, n) {
    if (!covers(auth[c], n)) return "";
    let str = "\n    http-request auth realm \"" + c + "\" unless { http_auth(basicauth:" + c + ") }";
    str += "\n    http-after-response set-header X-Robots-Tag \"noindex, nofollow\"";
    return str;
}

module.exports = { PORTS, parse_ports, access_users, build, covers, userlists, rule };

// node basicauth.js missing VE: the access users of VE with no .password yet.
if (require.main === module && process.argv[2] === "missing") {
    const datastore = require("../datastore/lib.js");
    const c = process.argv[3];
    if (!datastore.containers[c]) {
        console.error("no such container: " + c);
        process.exit(1);
    }
    for (const u of access_users(datastore.containers, datastore.users, c)) if (read_password(process.env.SC_DATASTORE_DIR, u) === null) console.log(u);
}
