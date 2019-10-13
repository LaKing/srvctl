#!/bin/node

/*srvctl */

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
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const dot = ".";
const root = "root";
const br = "\n";

if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

if (process.env.NOW !== undefined) NOW = process.env.NOW;
else NOW = new Date().toISOString();

if (process.env.SC_ON_HS !== undefined) ON_HS = process.env.ON_HS;
else ON_HS = false;
const SC_ON_HS = ON_HS;

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os = require("os");
const HOSTNAME = os.hostname();
const SC_HOSTNET = Number(process.env.SC_HOSTNET);
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;

// includes
var fs = require("fs");

function return_error(msg) {
    console.error("DATA-ERROR (lib):", msg);
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

//exports.load_hosts = function() { load_hosts(); };
var hosts = load_hosts();
exports.hosts = hosts;

function load_users() {
    try {
        return JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
        //if (users.root === undefined) {
        //    users.root = {};
        //    users.root.id = 0;
        //    users.root.uid = 0;
        //    users.root.reseller = 'root';
        //    users.root.reseller_id = 0;
        //}
    } catch (err) {
        return_error("READFILE " + SC_USERS_DATA_FILE + " " + err);
    }
}

var users = load_users();
exports.users = users;

function load_resellers() {
    var resellers = {};
    Object.keys(users).forEach(function(i) {
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
            fs.writeFile(SC_USERS_DATA_FILE, JSON.stringify(users, null, 2), function(err) {
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
            fs.writeFile(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2), function(err) {
                if (err) return_error("WRITEFILE " + err);
                else msg("wrote containers.json");
            });
        } catch (err) {
            return_error("WRITEFILE " + SC_CONTAINERS_DATA_FILE + " " + err);
        }
}

exports.write_containers = write_containers;

function container_uid(container) {
    var cipa = container.ip.split(dot);
    return 65536 * (Number(cipa[2]) * 255 + Number(cipa[3]));
}

exports.container_uid = container_uid;

function container_br(container) {
    // if there is a bridge defined in the datastore json, use that
    if (container.br) return container.br;
    // otherwise do the math
    var cipa = container.ip.split(dot);
    return "10" + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "x";
}

exports.container_br = container_br;

function container_gw(container) {
    var cipa = container.ip.split(dot);
    return Number(cipa[0]) + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "1";
}

exports.container_gw = container_gw;

function container_interface_name(container) {
    if (container.interface) return container.interface;
    var cipa = container.ip.split(dot);
    if (Number(cipa[0]) === 192) return Number(cipa[1]) + "_" + Number(cipa[2]) + "_" + Number(cipa[3]);
    if (Number(cipa[0]) === 172) return Number(cipa[1]) + "+" + Number(cipa[2]) + "+" + Number(cipa[3]);

    return Number(cipa[1]) + "-" + Number(cipa[2]) + "-" + Number(cipa[3]);
}

exports.container_interface_name = container_interface_name;

function container_bridge_host_ip(container) {
    var cipa = container.ip.split(dot);
    return "10" + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + "1";
}

exports.container_bridge_host_ip = container_bridge_host_ip;

function container_user_id(container) {
    var cipa = container.ip.split(dot);
    return Number(cipa[2]);
}

exports.container_user_id = container_user_id;

function container_check_user_ip_match(container) {
    var cipa = container.ip.split(dot);
    if (users[container.user].user_id === Number(cipa[2])) return true;
    return false;
}

exports.container_check_user_ip_match = container_check_user_ip_match;

function container_hostnet(container) {
    return container.ip.split(dot)[1];
}

exports.container_hostnet = container_hostnet;

function container_host(container) {
    var hostnet = container_hostnet(container);
    var ret;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet) ret = i;
    });
    return ret;
}

exports.container_host = container_host;

function container_host_ip(container) {
    var hostnet = container_hostnet(container);
    var ret = "ERROR datastore/lib.js: container_host_ip not found";
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet) ret = hosts[i].host_ip;
    });
    return ret;
}

exports.container_host_ip = container_host_ip;

function container_reseller_user(container) {
    if (users[container.user].reseller_id !== undefined) return container.user;
    if (users[container.user].reseller !== undefined) return users[container.user].reseller;
    return "root";
}

exports.container_reseller_user = container_reseller_user;

function container_user(container) {
    var cipa = container.ip.split(dot);
    var reseller = container_reseller_user(container);
    var ret = "root";
    Object.keys(users).forEach(function(i) {
        if (users[i].reseller == reseller) if (users[i].id === cipa[2]) ret = i;
    });
    return ret;
}

function container_http_port(container) {
    if (container.http_port) return container.http_port;
    else return 80;
}

exports.container_http_port = container_http_port;

function container_https_port(container) {
    if (container.https_port) return container.https_port;
    else return 443;
}

exports.container_https_port = container_https_port;

function container_resolv_conf(container) {
    return "nameserver " + container_gw(container) + "\n";
}

exports.container_resolv_conf = container_resolv_conf;

function container_nspawn_network_ethernet(container) {
    if (container.bridge) return "Bridge=" + container.bridge + "\n";
    return "VirtualEthernetExtra=" + container_interface_name(container) + "\n";
}

//exports.container_nspawn_network_ethernet = container_nspawn_network_ethernet;

function container_network_ethernet_network(container) {
    var str = "## srvctl-generated";

    if (container.bridge) {
        str += "[Match]" + "\n";
        str += "Virtualization=container" + "\n";
        str += "Name=host0" + "\n";
        str += "\n";
        str += "[Network]" + "\n";
        str += "DHCP=yes" + "\n";
        str += "LinkLocalAddressing=yes" + "\n";
        str += "LLDP=yes" + "\n";
        str += "EmitLLDP=customer-bridge" + "\n";
        str += "\n";
        str += "[DHCP]" + "\n";
        str += "UseTimezone=yes" + "\n";
        return str;
    } else {
        str += "[Match]" + "\n";
        str += "Virtualization=container" + "\n";
        str += "Name=" + container_interface_name(container) + "\n";
        str += "" + "\n";
        str += "[Network]" + "\n";
        str += "Address=" + container.ip + "/24" + "\n";
        str += "Gateway=" + container_gw(container) + "\n";
        str += "\n";
        str += "[DHCP]" + "\n";
        str += "UseTimezone=yes" + "\n";
        return str;
    }
}

exports.container_network_ethernet_network = container_network_ethernet_network;

function container_hosts(C) {
    var container = containers[C];
    var str = "## srvctl-generated";

    str += "127.0.0.1   localhost localhost.localdomain localhost4 localhost4.localdomain4" + "\n";
    str += "::1         localhost localhost.localdomain localhost6 localhost6.localdomain6" + "\n";

    str += container.ip + " " + C + "\n";
    str += container_gw(container) + " srvctl-gateway" + "\n";

    return str;
}

exports.container_hosts = container_hosts;

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

function container_nspawn_network_mapped_ports(container) {
    if (container.mapped_ports) {
        var str = "";
        for (let i in container.mapped_ports) {
            let p = container.mapped_ports[i];
            str += "## " + p.comment + "\n";
            str += "Port=" + p.proto + ":" + p.host_port + ":" + p.container_port + "\n";
        }
        return str;
    } else return "## no mapped ports";
}

//exports.container_nspawn_network_mapped_ports = container_nspawn_network_mapped_ports;

function container_nspawn(C) {
    var container = containers[C];
    var str = "## srvctl generated - " + C + "\n";
    str += "[Network]" + "\n";
    str += container_nspawn_network_ethernet(container);
    str += container_nspawn_network_mapped_ports(container);
    str += "" + "\n";
    str += "[Exec]" + "\n";
    str += "#PrivateUsers=" + container_uid(container) + "\n";
    str += "" + "\n";
    str += "[Files]" + "\n";
    str += "#PrivateUsersChown=true" + "\n";
    str += "BindReadOnly=" + process.env.SC_INSTALL_DIR + "\n";
    str += "BindReadOnly=/var/srvctl3/share/containers/" + C + "\n";
    str += "BindReadOnly=/var/srvctl3/share/common" + "\n";
    str += "BindReadOnly=/srv/" + C + "/network:/etc/systemd/network" + "\n";
    // Preventiv security. This might couse some trouble at a container update, but it is possibly neccessery due to the way .network files are processed. TODO - check the status of this.
    str += "BindReadOnly=/usr/lib/systemd/network:/usr/lib/systemd/network" + "\n";
    str += "BindReadOnly=/var/srvctl3/share/lock:/run/systemd/network" + "\n";
    str += "" + "\n";
    str += "BindReadOnly=/srv/" + C + "/hosts:/etc/hosts" + "\n";
    str += "" + "\n";
    return str;
}

exports.container_nspawn = container_nspawn;

function container_br_netdev(container) {
    if (container.bridge) return return_error("A container with a bridge shall not have a virtual br.");
    var str = "## srvctl generated\n";
    str += "[NetDev]" + "\n";
    str += "Name=" + container_br(container) + "\n";
    str += "Kind=bridge" + "\n";
    return str;
}

exports.container_br_netdev = container_br_netdev;

function container_br_network(container) {
    if (container.bridge) return return_error("A container with a bridge shall not have a virtual br.");
    var str = "## srvctl generated\n";
    str += "[Match]" + "\n";
    str += "Name=" + container_br(container) + "\n";
    str += "" + "\n";
    str += "[Network]" + "\n";
    str += "IPMasquerade=yes" + "\n";
    str += "Address=" + container_gw + "/24" + "\n";
    return str;
}

exports.container_br_network = container_br_network;

function container_firewall_commands(container, name) {
    if (container.mapped_ports) {
        var str = "";
        for (let i in container.mapped_ports) {
            let p = container.mapped_ports[i];
            //str += "## " + p.comment + "\n";
            //if (str.length > 0) str += " && ";
            str += "firewalld_add_service port-" + p.host_port + " " + p.proto + " " + p.host_port + " " + name + "  \n";
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

function find_next_cip_for_container_on_network(network) {
    var nipa = network.split(dot);
    var c = 2;
    Object.keys(containers).forEach(function(i) {
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
/*
function get_reseller_id(user) {
    
    //var user_id = Number(user.user_id);
    //var reseller_id = 0; 
    //if (user.reseller === undefined) user.reseller = root;
    //if (resellers[user.reseller] === undefined) return_error(user.reseller + " could not be located under the list of resellers");
    //if (resellers[user.reseller].reseller_id === undefined) return_error(user.reseller + " RESELLER_ID could not be located.");
    //reseller_id = Number(resellers[user.reseller].reseller_id);
    
    if (users[user].reseller === undefined) return 0;
    var n = Number(resellers[users[user].reseller].reseller_id);
    if (n >= 0) return n;
    else return_error("failed to find reseller id");
}
*/

function get_user_id() {
    //if (users[SC_USER].reseller_id !== undefined) return_error("Could not find reseller_id for " + SC_USER);
    var ret = Number(users[SC_USER].user_id);
    if (ret === undefined) return_error("failed to find user id");
    return ret;
}

// username actually
function get_user_uid(u) {
    if (users[u] === undefined) return_error("User could not be located");
    if (users[u].uid !== undefined) return users[u].uid;

    var ret = 1000;
    Object.keys(users).forEach(function(i) {
        if (Number(users[i].uid) >= ret) ret = Number(users[i].uid) + 1;
    });

    if (ret > 65530) return_error("Could not find a valid user uid, out of range. " + user);
    users[u].uid = ret;
    write_users();
    return ret;
}

exports.get_user_uid = get_user_uid;

// users uid is between 1000 and 10000
function get_next_user_id() {
    var ret = 1;
    Object.keys(users).forEach(function(i) {
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
    users[username] = user;

    get_user_uid(username);
}

exports.new_user = new_user;

function new_reseller(username) {
    if (users[username] !== undefined) return_error("USER EXISTS");
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;

    user.reseller = username;
    var rid = 1;
    Object.keys(users).forEach(function(i) {
        if (users[i].reseller_id >= rid) rid = users[i].reseller_id + 1;
    });
    user.reseller_id = rid;

    users[username] = user;

    get_user_uid(username);
}

exports.new_reseller = new_reseller;

function new_container(C, T) {
    if (containers[C] !== undefined) return_error("CONTAINER EXISTS");

    var container = {};
    var U = SC_USER;

    container.user = U;

    container.ip = find_ip_for_container();

    container.creation_time = NOW;
    //container.creation_host = HOSTNAME;
    container.type = T;

    containers[C] = container;
    //save_containers = true;
    write_containers();
}

exports.new_container = new_container;

function update_container_ip(C) {
    var a = SC_HOSTNET;
    var b = Number(users[containers[C].user].user_id);
    var c = find_next_cip_for_container_on_network("10." + a + dot + b + dot + "x");

    containers[C].ip = "10." + a + dot + b + dot + c;
    write_containers();
    msg("Update container " + C + " ip " + containers[C].ip);

    return;
}

exports.update_container_ip = update_container_ip;

function cluster_etc_hosts() {
    var str = "";
    str += "## $SRVCTL generated" + br;
    str += "127.0.0.1    localhost.localdomain localhost " + HOSTNAME + br;
    str += "::1    localhost6.localdomain6 localhost6" + br;
    str += "## hosts" + br;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip) str += hosts[i].host_ip + "    " + i + br;
        if (hosts[i].hostnet) str += "10.15." + hosts[i].hostnet + ".0    " + i.split(".")[0] + br;
    });
    str += "## containers" + br;
    Object.keys(containers).forEach(function(i) {
        if (containers[i].ip) {
            str += containers[i].ip + "    " + i + br;
            if (containers["mail." + i] === undefined) str += containers[i].ip + "    mail." + i + br;
        }
    });
    fs.writeFile("/etc/hosts", str, function(err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("wrote /etc/hosts");
    });
}

exports.cluster_etc_hosts = cluster_etc_hosts;

function cluster_postfix_relaydomains() {
    var str = "";
    var rd = [];
    Object.keys(hosts).forEach(function(i) {
        rd.push(i);
    });
    Object.keys(containers).forEach(function(i) {
        if (i.substring(0, 5) === "mail.") rd.push(i.substring(5));
        else rd.push(i);
    });

    // create string
    [...new Set(rd)].forEach(function(i) {
        str += i + " #" + br;
    });

    fs.writeFile("/etc/postfix/relaydomains", str, function(err) {
        if (err) return_error("WRITEFILE " + err);
        else msg("datastore -> postfix relaydomains");
    });
}

exports.cluster_postfix_relaydomains = cluster_postfix_relaydomains;

function cluster_host_keys() {
    var str = "";
    Object.keys(hosts).forEach(function(i) {
        Object.keys(hosts[i]).forEach(function(j) {
            if (j.substring(0, 8) === "host-key") str += hosts[i][j] + br;
        });
    });
    Object.keys(containers).forEach(function(i) {
        Object.keys(containers[i]).forEach(function(j) {
            if (j.substring(0, 8) === "host-key") str += containers[i][j] + br;
        });
    });
    fs.writeFile("/etc/ssh/ssh_known_hosts", str, function(err) {
        if (err) return_error("WRITEFILE " + err);
        else console.log("[ OK ] ssh known_hosts");
    });
}

exports.cluster_host_keys = cluster_host_keys;

function cluster_user_list() {
    var str = "";
    Object.keys(users).forEach(function(i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_user_list = cluster_user_list;

function cluster_container_list() {
    var str = "";
    Object.keys(containers).forEach(function(i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_container_list = cluster_container_list;

function user_container_list() {
    var str = "";
    Object.keys(containers).forEach(function(i) {
        if (containers[i].user === SC_USER) str += i + " ";
        else if (users[containers[i].user].reseller === SC_USER) str += i + " ";
    });
    return str;
}

exports.user_container_list = user_container_list;

function cluster_host_list() {
    var str = "";
    Object.keys(hosts).forEach(function(i) {
        str += i + " ";
    });
    return str;
}

exports.cluster_host_list = cluster_host_list;

function cluster_host_ip_list() {
    var str = "";
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip !== undefined) str += hosts[i].host_ip + " ";
    });
    return str;
}

exports.cluster_host_ip_list = cluster_host_ip_list;

/*
exports.# = function() {
    return #();
};
*/
