#!/bin/node

/*srvctl */

/*
 *  modules/datastore/lib.js — the datastore model / derivation library.
 *
 *  Loads hosts.json, users.json and containers.json from $SC_DATASTORE_DIR
 *  at require() time and exports:
 *    - pure derivations: container uid/br/gw/interface/host/reseller/ports/
 *      quota, user_uid, the cluster_* list functions
 *    - text generators: nspawn/network/hosts/resolv.conf/firewall snippets,
 *      cluster-wide /etc/hosts, postfix relaydomains, ssh known_hosts
 *    - mutators: new_user/new_reseller/new_container, container_update_ip,
 *      container_add_mapped_port, write_users/write_containers
 *  Consumed only by main.js (one node process per verb call from
 *  libs/bashlib.sh).
 *
 *  Conventions relied on farm-wide (do not change):
 *    - container ip scheme 10.<SC_HOSTNET>.<user_id>.<c>, c starts at 2,
 *      above 250 is fatal;  container_uid = 65536 * (user_id * 255 + c)
 *    - interface naming by first octet: 192.a.b.c -> a_b_c, 172 -> a+b+c,
 *      otherwise b-c-d;  default bridge name 10.<b>.<c>.x
 *    - errors print "LIB-ERROR:" on stderr and exit 112; an empty value
 *      sets exit code 100 (the "optional value missing" signal)
 *
 *  Scheduled for a full .mjs rewrite in v4; this pass is comments only.
 */

const lablib = "../../lablib.js";
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/hosts.json";
const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/users.json";
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + "/containers.json";
// FIXME(v4): dead readonly guard — SC_DATASTORE_RO is never exported anywhere
// in the repo (bash uses the unexported SC_DATASTORE_RO_USE), so the readonly
// check in write_users/write_containers below never fires: in readonly mode
// put/new/del/add/cfg still write the json files into the RO datastore and
// only the git commit is skipped (libs/gitlib.sh). Unify on one variable and
// enforce it here in the rewrite.
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const SC_COMPANY_DOMAIN = process.env.SC_COMPANY_DOMAIN;
const dot = ".";
const root = "root";
const br = "\n";

// FIXME(v4): SC_USER, NOW and ON_HS are implicit globals (no var/const/let);
// they would throw under strict mode. SC_ON_HS/ON_HS are computed but never
// used (and the ON_HS branch tests SC_ON_HS yet reads ON_HS) — dead code.
if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

if (process.env.NOW !== undefined) NOW = process.env.NOW;
else NOW = new Date().toISOString();

if (process.env.SC_ON_HS !== undefined) ON_HS = process.env.ON_HS;
else ON_HS = false;
const SC_ON_HS = ON_HS;

const SRVCTL = process.env.SRVCTL;
const SC_UID0 = process.env.SC_UID0;
const os = require("os");
const HOSTNAME = os.hostname();
const SC_HOSTNET = Number(process.env.SC_HOSTNET);
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;

// includes
var fs = require("fs");

function return_error(msg) {
    console.error("LIB-ERROR:", msg);
    process.exitCode = 112;
    process.exit(112);
}

function return_value(msg) {
    if (msg === undefined || msg === "") process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function load_hosts() {
    var results;

    try {
        results = JSON.parse(fs.readFileSync(SC_HOSTS_DATA_FILE));
    } catch (err) {
        return_error("READFILE " + SC_HOSTS_DATA_FILE + " " + err);
    }

    if (Object.keys(results).length < 1) return_error("READFILE " + SC_HOSTS_DATA_FILE + " has no hosts defined. Eventually run: srvctl update-install");

    return results;
}

var hosts = load_hosts();
exports.hosts = hosts;

function load_users() {
    try {
        return JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
    } catch (err) {
        return_error("READFILE " + SC_USERS_DATA_FILE + " " + err);
    }
}

var users = load_users();
exports.users = users;

function load_resellers() {
    var resellers = {};
    Object.keys(users).forEach(function (i) {
        if (users[i].reseller_id !== undefined) resellers[i] = users[i];
    });
    return resellers;
}

var resellers = load_resellers();
exports.resellers = resellers;

function load_containers() {
    try {
        return JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error("READFILE " + SC_CONTAINERS_DATA_FILE + " " + err);
    }
}

var containers = load_containers();
exports.containers = containers;

function write_users() {
    if (SC_DATASTORE_RO) return_error("Readonly datastore.");
    else
        try {
            fs.writeFile(SC_USERS_DATA_FILE, JSON.stringify(users, null, 2), function (err) {
                if (err) return_error("WRITEFILE " + err);
                else msg("wrote users.json");
            });
        } catch (err) {
            return_error("WRITEFILE " + SC_USERS_DATA_FILE + " " + err);
        }
}

exports.write_users = write_users;

function write_containers() {
    if (SC_DATASTORE_RO) return_error("Readonly datastore.");
    else
        try {
            fs.writeFile(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2), function (err) {
                if (err) return_error("WRITEFILE " + err);
                else msg("wrote containers.json");
            });
        } catch (err) {
            return_error("WRITEFILE " + SC_CONTAINERS_DATA_FILE + " " + err);
        }
}

exports.write_containers = write_containers;

function container_uid(C) {
    var container = containers[C];
    var b = Number(users[container.user].user_id);
    var c = 1;
    // a custom bridge container may have no ip in the datastore yet
    if (container.ip) c = Number(container.ip.split(dot)[3] || 1);
    return 65536 * (b * 255 + c);
}

exports.container_uid = container_uid;

function container_br(C) {
    var container = containers[C];
    // if there is a bridge defined in the datastore json, use that
    if (container.br) return container.br;
    // otherwise do the math
    var cipa = container.ip.split(dot);
    return "10" + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "x";
}

exports.container_br = container_br;

// the default srvctl gateway
function container_gw(C) {
    var container = containers[C];
    if (container.gateway) return container.gateway;
    var cipa = container.ip.split(dot);
    return Number(cipa[0]) + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "1";
}

exports.container_gw = container_gw;

function container_interface(C) {
    var container = containers[C];
    if (container.interface) return container.interface;

    var cipa = container.ip.split(dot);
    if (Number(cipa[0]) === 192) return Number(cipa[1]) + "_" + Number(cipa[2]) + "_" + Number(cipa[3]);
    if (Number(cipa[0]) === 172) return Number(cipa[1]) + "+" + Number(cipa[2]) + "+" + Number(cipa[3]);

    return Number(cipa[1]) + "-" + Number(cipa[2]) + "-" + Number(cipa[3]);
}

exports.container_interface = container_interface;

function container_br_host_ip(C) {
    var container = containers[C];
    var cipa = container.ip.split(dot);
    return "10" + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "1";
}

exports.container_br_host_ip = container_br_host_ip;

// when using a custom bridge
function container_bridge(C) {
    var container = containers[C];
    if (container.bridge) return container.bridge;
    return false;
}

exports.container_bridge = container_bridge;

function container_user_id(C) {
    var container = containers[C];
    return Number(users[container.user].user_id);
}

exports.container_user_id = container_user_id;

function container_user_ip_match(C) {
    var container = containers[C];
    if (container.bridge) return true;
    var cipa = container.ip.split(dot);
    if (users[container.user].user_id === Number(cipa[2])) return true;
    return false;
}

exports.container_user_ip_match = container_user_ip_match;

function container_hostnet(C) {
    var container = containers[C];
    // propably irrelevant if using a custom bridge
    if (container.bridge) return SC_HOSTNET;
    return container.ip.split(dot)[1];
}

exports.container_hostnet = container_hostnet;

function container_host(C) {
    var container = containers[C];

    // confucius, this got propably outdated in time. Not sure if we need this.
    if (fs.existsSync("/srv/" + C + "/rootfs")) return HOSTNAME;

    var hostnet = container_hostnet(C);
    var ret;
    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].hostnet == hostnet) ret = i;
    });
    return ret;
}

exports.container_host = container_host;

function container_host_ip(C) {
    var container = containers[C];
    var hostnet = container_hostnet(C);
    var ret = "ERROR datastore/lib.js: container_host_ip not found";
    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].hostnet == hostnet) ret = hosts[i].host_ip;
    });
    return ret;
}

exports.container_host_ip = container_host_ip;

function container_reseller(C) {
    var container = containers[C];
    if (users[container.user].reseller_id !== undefined) return container.user;
    if (users[container.user].reseller !== undefined) return users[container.user].reseller;
    return "root";
}

exports.container_reseller = container_reseller;

// FIXME(v4): dead code — container_user is not exported and has no callers
// (it also compares the numeric users[i].id against a string ip octet, so it
// could never match); drop it in the rewrite.
function container_user(C) {
    var container = containers[C];
    var cipa = container.ip.split(dot);
    var reseller = container_reseller(C);
    var ret = "root";
    Object.keys(users).forEach(function (i) {
        if (users[i].reseller == reseller) if (users[i].id === cipa[2]) ret = i;
    });
    return ret;
}

function container_http_port(C) {
    var container = containers[C];
    if (container.http_port) return container.http_port;
    else return 80;
}

exports.container_http_port = container_http_port;

function container_https_port(C) {
    var container = containers[C];
    if (container.https_port) return container.https_port;
    else return 443;
}

exports.container_https_port = container_https_port;

function container_resolv_conf(C) {
    var container = containers[C];
    var str = "## srvctl generated" + br;
    if (container.ip) str += "nameserver " + container_gw(C) + br;
    if (hosts[HOSTNAME].dns1) str += "nameserver " + hosts[HOSTNAME].dns1 + br;
    if (hosts[HOSTNAME].dns2) str += "nameserver " + hosts[HOSTNAME].dns2 + br;
    str += "nameserver 8.8.8.8" + br;
    str += "nameserver 8.8.4.4" + br;
    return str;
}

exports.container_resolv_conf = container_resolv_conf;

function container_nspawn_network_ethernet(C) {
    var container = containers[C];
    let lines = "";
    if (!container.deprecated) lines += "VirtualEthernetExtra=" + container_interface(C) + br;
    if (container.bridge) lines += "Bridge=" + container.bridge + br;
    return lines;
}

//exports.container_nspawn_network_ethernet = container_nspawn_network_ethernet;

function container_ethernet(C) {
    var container = containers[C];

    var interface = container_interface(C);
    var ip_br = container_br(C);

    var str = "#!/bin/bash" + br;
    str += br;
    str += "if ip link set dev " + interface + " up" + br;
    str += "then" + br;
    str += "    echo '[ OK ] ip link set dev " + interface + " up'" + br;
    str += "else" + br;
    str += "    echo '[FAIL] ip link set dev " + interface + " up'" + br;
    str += "fi" + br;
    str += br;
    str += "if brctl addif " + ip_br + " " + interface + br;
    str += "then" + br;
    str += "    echo '[ OK ] brctl addif " + ip_br + " " + interface + "'" + br;
    str += "else" + br;
    str += "    echo '[FAIL] brctl addif " + ip_br + " " + interface + "'" + br;
    str += "fi" + br;
    str += br;
    str += "if firewall-cmd --zone=trusted --add-interface=" + ip_br + br;
    str += "then" + br;
    str += "    echo '[ OK ] fireall-cmd added " + ip_br + "  to the trusted interfaces'" + br;
    str += "else" + br;
    str += "    echo '[FAIL] fireall-cmd could not add " + ip_br + "  to the trusted interfaces'" + br;
    str += "fi" + br;
    str += br;
    str += "if firewall-cmd --permanent --zone=trusted --add-interface=" + ip_br + br;
    str += "then" + br;
    str += "    echo '[ OK ] fireall-cmd added " + ip_br + "  to the trusted interfaces'" + br;
    str += "else" + br;
    str += "    echo '[FAIL] fireall-cmd could not add " + ip_br + "  to the trusted interfaces'" + br;
    str += "fi" + br;
    return str;
}

exports.container_ethernet = container_ethernet;

function container_ethernet_network(C) {
    var container = containers[C];
    var str = "## srvctl-generated" + br;

    str += "[Match]" + br;
    str += "Virtualization=container" + br;
    str += "Name=" + container_interface(C) + br;
    str += "" + br;
    str += "[Network]" + br;
    str += "Address=" + container.ip + "/24" + br;
    str += "Gateway=" + container_gw(C) + br;
    str += "DNS=8.8.8.8" + br;
    str += br;

    return str;
}

exports.container_ethernet_network = container_ethernet_network;

function container_hosts(C) {
    var container = containers[C];
    var str = "## srvctl-generated for " + C + br;

    str += "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4 " + C + br;
    str += "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" + br;

    if (container.ip) {
        // seems this confuses curl in containers with https and certificates
        //str += container.ip + " " + C + br;
        str += container_gw(C) + " srvctl-gateway" + br;
    }
    return str;
}

exports.container_hosts = container_hosts;

function container_quota(C) {
    var container = containers[C];
    var str = "250000000";

    if (container.quota !== undefined) str = container.quota;

    return str;
}

exports.container_quota = container_quota;

/*

For example:
	"mapped_ports": [
      {
        "proto": "tcp",
        "host_port": 1100,
        "container_port": 1100,
        "comment": "VPN"
      },
      {
        "proto": "tcp",
        "host_port": 2022,
        "container_port": 22,
        "comment": "SSH"
      }
    ],

*/

function is_mapped_port(proto, n) {
    // ports reserved
    if (n >= 8000 && n <= 10000) return true;
    if (n >= 5900 && n <= 6000) return true;
    if (n < 1024) return true;

    var result = false;
    Object.keys(containers).forEach(function (i) {
        if (containers[i].mapped_ports)
            containers[i].mapped_ports.forEach(function (j) {
                if (j.proto === proto && j.host_port === n) result = true;
            });
    });
    return result;
}

function container_add_mapped_port(C) {
    var container = containers[C];
    if (!container.mapped_ports) container.mapped_ports = [];
    var o = {};
    o.proto = "tcp";
    var port_arg = process.argv[7];
    o.comment = process.argv.slice(7).join(" ");

    // TODO .. fix this fix
    // FIXME(v4): when no port argument is given, port_arg stays undefined and
    // the .indexOf call below throws an uncaught TypeError instead of a clean
    // return_error; the argv juggling should become an explicit
    // {proto, port, comment} argument in the rewrite.

    // sc cfg container container2 add_mapped_port udp 22 testing adding a mapped port
    if (process.argv[6] === "udp" || process.argv[6] === "tcp") o.proto = process.argv[6];

    // when passing OPAS over he command an additional containername slips into the parameters passed
    if (process.argv[7] === "udp" || process.argv[7] === "tcp") {
        o.proto = process.argv[7];
        port_arg = process.argv[8];
        o.comment = process.argv.slice(8).join(" ");
    }

    // or if the protocol is specified along with the port with a semicolon
    if (port_arg.indexOf(":") >= 0) {
        if (port_arg.split(":")[0] === "udp") o.proto = "udp";
        o.container_port = Number(port_arg.split(":")[1]);
    } else o.container_port = Number(port_arg);

    o.user = SC_USER;
    o.timestamp = NOW;

    if (o.container_port < 1) return_error("invalid port");
    if (o.container_port > 65535) return_error("invalid port");

    var port = o.container_port;
    if (port < 20) port = 1024 + port;
    if (port < 30) port = 2000 + port;
    if (port < 1024) port = 3000 + port;
    if (port > 5000 && port < 10000) port = port - 2000;

    for (i = port; i < 65535; i++) {
        if (is_mapped_port(o.proto, i)) continue;
        port = i;
        break;
    }

    o.host_port = port;

    msg("Registering " + o.proto + " port " + port + " for " + C + ":" + o.container_port);
    container.mapped_ports.push(o);
    write_containers();
}

exports.container_add_mapped_port = container_add_mapped_port;

function container_nspawn_network_mapped_ports(C) {
    var container = containers[C];
    if (container.mapped_ports) {
        var str = "";
        for (let i in container.mapped_ports) {
            let p = container.mapped_ports[i];
            str += "## " + p.comment + br;
            str += "Port=" + p.proto + ":" + p.host_port + ":" + p.container_port + br;
        }
        return str;
    } else return "## no mapped ports";
}

//exports.container_nspawn_network_mapped_ports = container_nspawn_network_mapped_ports;

/*

Private users rpm bug - therfore private users disabled for now. 

[root@mariadb-test root]# dnf -y -q install mariadb-server
Error unpacking rpm package mariadb-server-3:10.3.18-1.fc29.x86_64
Error: Transaction failed


*/

function container_useruids(C) {
    const container = containers[C];
    const root_uid = container_uid(C);

    let users_content = fs.readFileSync("/srv/" + C + "/rootfs/etc/passwd", "UTF8");
    let users_content_lines = users_content.split("\n");
    let users = {};
    for (let i = 0; i < users_content_lines.length; i++) {
        let ucl = users_content_lines[i].split(":");
        users[ucl[0]] = Number(ucl[2]);
    }

    let groups_content = fs.readFileSync("/srv/" + C + "/rootfs/etc/group", "UTF8");
    let groups_content_lines = groups_content.split("\n");
    let groups = {};
    for (let i = 0; i < groups_content_lines.length; i++) {
        let ucl = groups_content_lines[i].split(":");
        groups[ucl[0]] = Number(ucl[2]);
    }

    function chown(C, user, group, path) {
        if (!users[user]) return "## no user " + user + br;
        if (!groups[group]) return "## no group " + group + br;
        return (
            "[[ -d /srv/" +
            C +
            "/rootfs" +
            path +
            " ]] && chown -R " +
            Number(root_uid + users[user]) +
            ":" +
            Number(root_uid + groups[group]) +
            " /srv/" +
            C +
            "/rootfs" +
            path +
            " && echo '" +
            path +
            "'" +
            br
        );
    }

    var str = "## srvctl generated - for restore userids shell script" + C + br;
    str += "root_uid=" + container_uid(C) + br;
    str += "" + br;
    str += "#echo 'USERS " + JSON.stringify(users) + "'" + br;
    str += "#echo 'GROUP " + JSON.stringify(groups) + "'" + br;
    str += "" + br;

    str += chown(C, "codepad", "codepad", "/srv/codepad-project");
    str += chown(C, "apache", "apache", "/var/www/html");
    str += chown(C, "mysql", "mysql", "/var/lib/mysql");
    str += chown(C, "mongod", "mongod", "/var/lib/mongo");

    str += "# for u in /srv/" + C + "/rootfs" + br;
    str += "# do" + br;
    str += "#   ssh " + C + ' "sc add-user $u"' + br;
    str += "# done" + br;

    for (let u in users) {
        if (users[u] >= 1000) str += chown(C, u, u, "/home/" + u);
    }

    // leave root last
    str += chown(C, "root", "root", "/root");
    str += "" + br;
    str += br;
    return str;
}

exports.container_useruids = container_useruids;

function container_nspawn(C) {
    var container = containers[C];
    var str = "## srvctl generated - " + C + br;
    str += "[Network]" + br;
    str += container_nspawn_network_ethernet(C);
    str += container_nspawn_network_mapped_ports(C);
    str += br;
    str += "[Exec]" + br;
    str += "PrivateUsers=" + container_uid(C) + br;
    // Capability needed for mongo, the mongodb shell
    str += "Capability=CAP_IPC_LOCK" + br;
    // Capability needed for docker inside containers
    str += "SystemCallFilter=add_key keyctl bpf" + br;

    str += "" + br;
    str += "[Files]" + br;
    str += "PrivateUsersChown=true" + br;
    str += "BindReadOnly=" + process.env.SC_INSTALL_DIR + br;
    str += "BindReadOnly=/var/srvctl3/share/containers/" + C + br;
    str += "BindReadOnly=/var/srvctl3/share/common" + br;
    str += "BindReadOnly=/srv/" + C + "/network:/etc/systemd/network" + br;
    // Preventiv security. This might couse some trouble at a container update, but it is [WAS] possibly neccessery due to the way .network files are processed. TODO - check the status of this.
    // Since we have now an advanced networking setup system, this seems to be obsolete. Users may hack the ip with container root access but wont get the right bridge on the host side. TODO test it.
    // str += "BindReadOnly=/usr/lib/systemd/network:/usr/lib/systemd/network" + br;
    // str += "BindReadOnly=/var/srvctl3/share/lock:/run/systemd/network" + br;
    str += br;
    str += "BindReadOnly=/srv/" + C + "/hosts:/etc/hosts" + br;
    str += br;
    return str;
}

exports.container_nspawn = container_nspawn;

function container_br_netdev(C) {
    var container = containers[C];
    //if (container.bridge) return return_error("A container with a bridge shall not have a virtual br.");
    var str = "## srvctl generated" + br;
    str += "[NetDev]" + br;
    str += "Name=" + container_br(C) + br;
    str += "Kind=bridge" + br;
    return str;
}

exports.container_br_netdev = container_br_netdev;

function container_br_network(C) {
    var container = containers[C];
    //if (container.bridge) return return_error("A container with a bridge shall not have a virtual br.");
    var str = "## srvctl generated" + br;
    str += "[Match]" + br;
    str += "Name=" + container_br(C) + br;
    str += br;
    str += "[Network]" + br;
    str += "IPMasquerade=ipv4" + br;
    str += "Address=" + container_gw(C) + "/24" + br;
    // https://github.com/systemd/systemd/issues/9252
    str += "ConfigureWithoutCarrier=yes";
    return str;
}

exports.container_br_network = container_br_network;

function container_firewall_commands(C) {
    var container = containers[C];
    if (container.mapped_ports) {
        var str = "";
        for (let i in container.mapped_ports) {
            let p = container.mapped_ports[i];
            //str += "## " + p.comment + "\n";
            //if (str.length > 0) str += " && ";
            str += "firewalld_add_service port-" + p.host_port + " " + p.proto + " " + p.host_port + " " + C + br;
        }
        return str;
    } else return "## no mapped ports";
}

exports.container_firewall_commands = container_firewall_commands;

function container_mx(C) {
    if (containers[C].use_gsuite) return false;
    if (C.substring(0, 5) === "mail.") return true;
    if (containers[C].mx !== undefined) return containers[C].mx;
    if (containers["mail." + C] !== undefined) return false;
    return true;
}

exports.container_mx = container_mx;

function container_domains(name) {
    let domains = [];
    if (name.indexOf(".") > 0) {
        domains.push(name);
        domains.push("www." + name);
    }
    // aliases do redirects and forwards
    if (containers[name].aliases) {
        for (let i in containers[name].aliases) {
            let domain = containers[name].aliases[i];
            domains.push(domain);
            domains.push("www." + domain);
        }
    }
    // altnames are direct alternative names, no redirects or forwards
    if (containers[name].altnames) {
        for (let i in containers[name].altnames) {
            let domain = containers[name].altnames[i];
            domains.push(domain);
            domains.push("www." + domain);
        }
    }
    // subdomains are extra labels under the container's own name, e.g. "fox" -> fox.<fqdn>.
    // Expand against the normalized fqdn so dotless container names get the company domain
    // appended (v4-devel -> v4-devel.d250.hu -> fox.v4-devel.d250.hu). A *.<parent> wildcard
    // only matches a single label, so fox.v4-devel.d250.hu is NOT covered by *.d250.hu and
    // needs its own certificate. No www. variant — these are leaf names served by the same
    // container (haproxy already routes *.<name> via subacl).
    if (containers[name].subdomains) {
        let fqdn = normalize_container_domain(name);
        for (let i in containers[name].subdomains) {
            domains.push(containers[name].subdomains[i] + "." + fqdn);
        }
    }
    return domains;
}

exports.container_domains = container_domains;

function normalize_container_domain(name) {
    if (!SC_COMPANY_DOMAIN) return name;

    if (name.substring(0, 5) === "mail.") {
        const base = name.substring(5);
        if (base.indexOf(dot) < 0) return "mail." + base + dot + SC_COMPANY_DOMAIN;
        return name;
    }

    if (name.indexOf(dot) < 0) return name + dot + SC_COMPANY_DOMAIN;
    return name;
}

function normalize_mail_domain(name) {
    if (name.substring(0, 5) === "mail.") name = name.substring(5);
    if (name.indexOf(dot) < 0 && SC_COMPANY_DOMAIN) return "mail." + name + dot + SC_COMPANY_DOMAIN;
    return "mail." + name;
}

// internal function for default network ip calculation
function find_next_cip_for_container_on_network(network) {
    var nipa = network.split(dot);
    var c = 2;
    Object.keys(containers).forEach(function (i) {
        //if (containers[i].bridge) return;
        var cipa = containers[i].ip.split(dot);
        if (cipa[1] === nipa[1] && cipa[2] === nipa[2]) {
            var cc = Number(cipa[3]);
            if (cc >= c) c = cc + 1;
        }
    });
    // TODO reuse existing holes in case it has run out.
    if (c > 250) return_error("out of range in find_next_cip_for_container_on_network " + network);
    return c;
}

function get_user_id() {
    var ret = Number(users[SC_USER].user_id);
    if (ret === undefined) return_error("failed to find user id");
    return ret;
}

function user_uid(u) {
    if (users[u]) if (users[u].uid !== undefined) return users[u].uid;

    var ret = 1000;
    Object.keys(users).forEach(function (i) {
        if (Number(users[i].uid) >= ret) ret = Number(users[i].uid) + 1;
    });

    if (ret > 65530) return_error("Could not find a valid user uid, out of range. " + user);
    return ret;
}

exports.user_uid = user_uid;

// users uid is between 1000 and 10000
function get_next_user_id() {
    var ret = 1;
    Object.keys(users).forEach(function (i) {
        if (Number(users[i].user_id) >= ret) ret = Number(users[i].user_id) + 1;
    });
    if (ret > 255) return_error("Out of range. Can not allocate user_id");
    else return ret;
}

function find_ip_for_container() {
    var a = SC_HOSTNET;
    var b = get_user_id();
    var c = find_next_cip_for_container_on_network("10." + a + dot + b + dot + "x");

    return "10." + a + dot + b + dot + c;
}

function new_user(username) {
    if (users[username] !== undefined) return_error("USER EXISTS");
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;

    if (users[SC_USER].reseller_id === undefined) return_error("MISSING RESELLER_ID");

    user.reseller = SC_USER;
    user.user_id = get_next_user_id();

    user.uid = user_uid(username);

    users[username] = user;
    write_users();
}

exports.new_user = new_user;

function new_reseller(username) {
    if (users[username] !== undefined) return_error("USER EXISTS");
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;

    user.reseller = username;
    var rid = 1;
    Object.keys(users).forEach(function (i) {
        if (users[i].reseller_id >= rid) rid = users[i].reseller_id + 1;
    });
    user.reseller_id = rid;
    user.uid = user_uid(username);
    users[username] = user;
    write_users();
}

exports.new_reseller = new_reseller;

function new_container(C, T, B) {
    if (containers[C] !== undefined) return_error("CONTAINER EXISTS");

    var container = {};

    // FIXME(v4): stray debug output on every container creation (captured
    // into the bashlib `new` error variable via 2>&1, but still noise).
    console.log(C, T, B);

    container.user = SC_USER;

    // an ip is always allocated, even when a custom bridge is given
    if (B) container.bridge = B;
    container.ip = find_ip_for_container();

    container.creation_time = NOW;
    container.type = T;

    containers[C] = container;
    write_containers();
}

exports.new_container = new_container;

function container_update_ip(C) {
    var container = containers[C];

    var a = SC_HOSTNET;
    var b = Number(users[container.user].user_id);
    var c = find_next_cip_for_container_on_network("10." + a + dot + b + dot + "x");

    container.ip = "10." + a + dot + b + dot + c;
    write_containers();
    msg("Update container " + C + " ip " + container.ip);

    return;
}

exports.container_update_ip = container_update_ip;

function cluster_etc_hosts() {
    var str = "";
    str += "## $SRVCTL generated" + br;
    str += "127.0.0.1    localhost.localdomain localhost " + HOSTNAME + br;
    str += "::1    localhost6.localdomain6 localhost6" + br;
    str += "## hosts" + br;
    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].host_ip) str += hosts[i].host_ip + "    " + i + br;
        if (hosts[i].hostnet) str += "10.15." + hosts[i].hostnet + ".0    " + i.split(".")[0] + br;
    });
    str += "## containers" + br;
    Object.keys(containers).forEach(function (i) {
        if (containers[i].ip) {
            str += containers[i].ip + "    " + i + br;
            if (i.indexOf(".") < 0) str += containers[i].ip + "    " + i + ".local" + br;
            if (i.indexOf(".") < 0) str += containers[i].ip + "    " + i + "." + process.env.SC_COMPANY_DOMAIN + br;

            if (containers["mail." + i] === undefined)
                if (containers[i].is_mail === false) str += "## [disabled] " + containers[i].ip + "    mail." + i + br;
                else {
                  str += containers[i].ip + "    mail." + i + br;
                  str += containers[i].ip + "    mail." + i + "." + process.env.SC_COMPANY_DOMAIN + br;
                }
            if (containers[i].aliases) {
                for (const alias of containers[i].aliases) {
                    str += containers[i].ip + "    " + alias + br;
                    if (containers["mail." + i] === undefined)
                        if (containers[i].is_mail === false) str += "## [disabled] " + containers[i].ip + "    mail." + alias + br;
                        else str += containers[i].ip + "    mail." + alias + br;
                }
            }
        }
    });
    return str;
}

exports.cluster_etc_hosts = cluster_etc_hosts;

function cluster_postfix_relaydomains() {
    var str = "";
    var rd = [];
    Object.keys(hosts).forEach(function (i) {
        rd.push(i);
    });
    Object.keys(containers).forEach(function (i) {
        if (i.substring(0, 5) === "mail.") rd.push(normalize_container_domain(i.substring(5)));
        else rd.push(normalize_container_domain(i));

        if (containers[i].aliases) for (const alias of containers[i].aliases) rd.push(normalize_container_domain(alias));
    });

    // create string
    [...new Set(rd)].forEach(function (i) {
        str += i + "\tOK" + br;
    });

    return str;
}

exports.cluster_postfix_relaydomains = cluster_postfix_relaydomains;

function cluster_host_keys() {
    var str = "";
    Object.keys(hosts).forEach(function (i) {
        Object.keys(hosts[i]).forEach(function (j) {
            if (j.substring(0, 8) === "host-key") str += hosts[i][j] + br;
        });
    });
    Object.keys(containers).forEach(function (i) {
        Object.keys(containers[i]).forEach(function (j) {
            if (j.substring(0, 8) === "host-key") str += containers[i][j] + br;
        });
    });
    return str;
}

exports.cluster_host_keys = cluster_host_keys;

function cluster_user_list() {
    var str = "";
    Object.keys(users).forEach(function (i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_user_list = cluster_user_list;

function cluster_container_list() {
    var str = "";
    Object.keys(containers).forEach(function (i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_container_list = cluster_container_list;

function user_container_list() {
    var str = " ";
    Object.keys(containers).forEach(function (i) {
        if (containers[i].user === SC_USER) str += i + " ";
        else if (users[containers[i].user].reseller === SC_USER) str += i + " ";
    });
    return str;
}

exports.user_container_list = user_container_list;

function cluster_host_list() {
    var str = "";
    Object.keys(hosts).forEach(function (i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_host_list = cluster_host_list;

function cluster_host_ip_list() {
    var str = "";
    Object.keys(hosts).forEach(function (i) {
        if (hosts[i].host_ip !== undefined) str += hosts[i].host_ip + " ";
    });
    return str;
}

exports.cluster_host_ip_list = cluster_host_ip_list;
