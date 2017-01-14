#!/bin/node

/*jshint esnext: true */

function log(msg) {
    console.log(msg);
}

const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];
const VAL = process.argv[6];

// constatnts

const SC_HOSTS_DATA_FILE = '/etc/srvctl/data/hosts.json';

const SC_USERS_DATA_FILE = '/srvctl/data/users.json';
const SC_CONTAINERS_DATA_FILE = '/srvctl/data/containers.json';

const PUT = 'put';
const GET = 'get';
const OUT = 'out';
const CFG = 'cfg';
const DEL = 'del';
const NEW = 'new';
const dot = '.';
const root = 'root';
// netblock size
const NBC = 16;


if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

if (process.env.NOW !== undefined) NOW = process.env.NOW;
else NOW = new Date().toISOString();


if (process.env.SC_ON_HS !== undefined) ON_HS = process.env.ON_HS;
else ON_HS = false;
const SC_ON_HS = ON_HS;

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const HOSTNAME = process.env.HOSTNAME;
const SC_HOSTNET = Number(process.env.SC_HOSTNET);
const SC_RESELLER_USER = process.env.SC_RESELLER_USER;


function exit() {
    if (save_containers) write_containers();
    if (save_users) write_users();
    process.exit(0);
}

function return_optional_value(msg) {
    if (msg !== undefined) console.log(msg);
    process.exit(0);
}

function return_value(msg) {
    if (msg !== undefined)
        console.log(msg);
    else return_error("Undefined value");
    process.exit(0);
}

function return_error(msg) {
    console.error('DATA-ERROR:', msg, process.argv);
    process.exit(10);
}

function output(variable, value) {
    console.log(variable + '="' + value + '"');
}

// get or put
if (CMD === undefined) return_error("MISSING CMD ARGUMENT");
// users or containers
if (DAT === undefined) return_error("MISSING DAT ARGUMENT");
// field
if (ARG === undefined) return_error("MISSING ARG ARGUMENT");
// OPA is optional

if (CMD !== GET && CMD !== PUT && CMD !== OUT && CMD !== CFG && CMD !== DEL && CMD !== NEW) return_error("INVALID CMD ARGUMENT: " + CMD);
if (DAT !== 'system' && DAT !== 'user' && DAT != 'container' && DAT != 'host' && DAT != 'reseller') return_error("INVALID DAT ARGUMENT: " + DAT);

// includes
var fs = require('fs');

// variables
var hosts = {};
var users = {};
var resellers = {};
var containers = {};
var user = '';
var container = '';
var save_users = false;
var save_containers = false;

//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

// data functions
function load_hosts() {
    try {
        hosts = JSON.parse(fs.readFileSync(SC_HOSTS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
    }
}
// data functions
function load_resellers() {
    resellers = {};
    resellers.root = users.root;
    resellers.root.is_reseller_id = 0;
    Object.keys(users).forEach(function(i) {
        if (users[i].is_reseller_id !== undefined)
            resellers[i]=users[i];
    });
}

function load_users() {
    try {
        users = JSON.parse(fs.readFileSync(SC_USERS_DATA_FILE));
        if (users.root === undefined) {
             users.root = {};
             users.root.id = 0;
             users.root.uid = 0;
             users.root.reseller = 'root';
             users.root.is_reseller_id = 0;
        }
        // resellers are also users
        load_resellers();
        
    } catch (err) {
        return_error('READFILE ' + SC_USERS_DATA_FILE + ' ' + err);
    }
}

function load_containers() {
    try {
        containers = JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
    }
}

function write_users() {
    try {
        fs.writeFileSync(SC_USERS_DATA_FILE, JSON.stringify(users, null, 2));
    } catch (err) {
        return_error('WRITEFILE ' + SC_USERS_DATA_FILE + ' ' + err);
    }
}

function write_containers() {
    try {
        fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
    } catch (err) {
        return_error('WRITEFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
    }
}


/* ------------------- //
SC CONTAINER NETBLOCKS (255)

0: network address
1: host-bridge ip
...
16: 
20: containers
200 containers
201: vpn-clients
250: vpn-clients
255: broadcast address

/* -------------------- */

function container_bridge_address(container) {
    var cipa = container.ip.split(dot);
    return '10' + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + 'x';
}

function container_reseller_id(container) {
    var cipa = container.ip.split(dot);
    var hostnet = Math.floor(cipa[1] / 16);
    var resellerid = cipa[1] - (16 * hostnet);
    return resellerid;
}

function container_hostnet(container) {
    var cipa = container.ip.split(dot);
    var hostnet = Math.floor(cipa[1] / 16);
    return hostnet;
}

function container_host(container) {
    var hostnet = container_hostnet(container);
    var ret;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet)
            ret = i;
    });
    return ret;
}

function container_host_ip(container) {
    var hostnet = container_hostnet(container);
    var ret;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet)
            ret = hosts[i].host_ip;
    });
    return ret;
}


function container_reseller_user(container) {
    var resellerid = container_reseller_id(container);
    var ret = 'root';
    Object.keys(resellers).forEach(function(i) {
        if (resellers[i].is_reseller_id == resellerid)
            ret = i;
    });
    return ret;
}

function container_user(container) {
    var cipa = container.ip.split(dot);
    var reseller = container_reseller_user(container);
    var ret = 'root';
    Object.keys(users).forEach(function(i) {
        if (users[i].reseller == reseller)
            if (users[i].id === cipa[2]) ret = i;
    });
    return ret;
}

function find_next_cip_for_container_on_network(network) {
    var nipa = network.split(dot);
    var c = 1;
    Object.keys(containers).forEach(function(i) {
        var cipa = containers[i].ip.split(dot);
        if (cipa[1] === nipa[1] && cipa[2] === nipa[2]) {
            var cc = Number(cipa[3]);
            if (cc >= c) c = cc + 1;
        }
    });
    if (c > 199) return_error("out of range in find_next_cip_for_container_on_network " + network);
    return c;
}

function get_reseller_id(user) {
    var n = Number(resellers[users[user].reseller].is_reseller_id);
    if (n >= 0) return n;
    else return_error("failed to find reseller id");
}

function get_user_id() {
    var ret = Number(users[SC_USER].id);
    if (ret === undefined) return_error("failed to find user id");
    return ret;
}

function get_user_uid(user) {
    if (user.uid !== undefined) return user.uid;
    
    var userid = Number(user.id);
    var resellerid = Number(resellers[user.reseller].is_reseller_id);
    if (userid >= 0 && resellerid >=0) return 10000 + resellerid * 1000 + userid;
    else return_error("failed to find user id/uid");    
}

function get_next_user_id(reseller) {
    var ret = 1;
    Object.keys(users).forEach(function(i) {
        if (users[i].reseller === reseller)
            if (Number(users[i].id) >= ret) ret = Number(users[i].id) + 1;
    });
    if (ret > 250) return_error("Out of range. Can not allocate user id for reseller " + reseller);
    else return ret;
}

function find_ip_for_container() {

    var a = (16 * SC_HOSTNET) + get_reseller_id(SC_USER);
    var b = get_user_id();
    var c = find_next_cip_for_container_on_network('10.' + a + dot + b + dot + 'x');

    return '10.' + a + dot + b + dot + c;
}

function random(items) {
    return items[Math.floor(Math.random() * items.length)];
}

function get_password() {
    var ad = ["ld", "ng", "nt", "lf", "br", "kr", "pr", "fr", "gr", "tr", "rt", "st", "x", "q", "w"];
    var aa = ["B", "C", "D", "F", "G", "H", "J", "K", "L", "M", "N", "P", "R", "S", "T", "V", "Z"];
    var ar = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"];
    var bb = ["a", "e", "i", "o", "u"];
    var bc = ["A", "E", "I", "O", "U"];
    var w1 = random([random(bc) + random(ad.concat(ar)), random(aa) + random(bb) + random(ar)]) + random(bb) + random(ad.concat(ar)) + random(bb);
    var w2 = random([random(bc) + random(ad.concat(ar)), random(aa) + random(bb) + random(ar)]) + random(bb) + random(ad.concat(ar)) + random(bb);
    return w1 + '-' + w2;
}

function new_user(username) {
    if (users[username] !== undefined) return_error('USER EXISTS');
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;
    user.password = get_password();
    
    if (resellers[SC_USER] !== undefined) user.reseller = SC_USER;
    else user.reseller = 'root';
    
    user.id = get_next_user_id(user.reseller);

    users[username] = user;
    save_users = true;
}

function add_project_to_user(P, U) {
    if (users[U] === undefined) new_user(U);
    var user = users[U];
    if (user.projects === undefined) user.projects = {};
    var projects = user.projects;
    if (projects[P] === undefined) {
        var project = {};
        project.containers = [];
        save_users = true;
        return project;
    }

    return projects[P];
}

function add_container_to_user(C, U) {
    if (users[U] === undefined) new_user(U);
    var user = users[U];
    if (user.projects === undefined) user.projects = {};

    var user_has_it = false;
    Object.keys(user.projects).forEach(function(i) {
        var p = user.projects[i];
        // if this project has this container
        if (p.containers !== undefined && p.containers.indexOf(C) > -1) user_has_it = true;
    });

    if (user_has_it) return;

    // new project, new container ...
    var project = add_project_to_user(C, U);
    project.containers.push(C);
    save_users = true;

}

function new_container(C, T) {

    if (containers[C] !== undefined) return_error('CONTAINER EXISTS');

    var container = {};
    var U = SC_USER;

    add_container_to_user(C, U);

    container.user = U;

    container.ip = find_ip_for_container();

    container.creation_time = NOW;
    //container.creation_host = HOSTNAME;
    container.type = T;

    containers[C] = container;
    save_containers = true;
}

function system_etc_hosts() {
    log("## srvctl generated");
    log("127.0.0.1    localhost.localdomain localhost");
    log("::1    localhost6.localdomain6 localhost6");
    log("## hosts");
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip) log(hosts[i].host_ip + '    ' + i);
    });
    log("## containers");
    Object.keys(containers).forEach(function(i) {
        if (containers[i].ip) {
            log(containers[i].ip + '    ' + i);
            if (containers["mail." + i] === undefined) log(containers[i].ip + '    mail.' + i);
        }
    });
}

function system_postfix_relaydomains() {
    Object.keys(hosts).forEach(function(i) {
        log(i + ' #');
    });
}

function system_ssh_config() {
    Object.keys(hosts).forEach(function(i) {
        log("Host " + i);
        log("User root");
        log("StrictHostKeyChecking no");
        log("");
    });
    Object.keys(containers).forEach(function(i) {
        log("Host " + i);
        log("User root");
        log("StrictHostKeyChecking no");
        log("");
    });
}

function system_host_keys() {
    Object.keys(hosts).forEach(function(i) {
        Object.keys(hosts[i]).forEach(function(j) {
            if (j.substring(0, 8) === 'host-key') log(hosts[i][j]);
        });
    });
    Object.keys(containers).forEach(function(i) {
        Object.keys(containers[i]).forEach(function(j) {
            if (j.substring(0, 8) === 'host-key') log(containers[i][j]);
        });
    });
}

function system_user_list() {
    var str = '';
    Object.keys(users).forEach(function(i) {
        str += i + ' ';
    });
    return_value(str);
}

function system_container_list() {
    var str = '';
    Object.keys(containers).forEach(function(i) {
        str += i + ' ';
    });
    return_value(str);
}

function system_host_list() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        str += i + ' ';
    });
    return_value(str);
}

function system_host_ip_list() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip !== undefined) str += hosts[i].host_ip + ' ';
    });
    return_value(str);
}

load_hosts();
load_containers();
load_users();

if (DAT === 'container') {

    if (CMD === NEW) {
        new_container(ARG, OPA);
        exit();
    }

    if (CMD === GET && OPA === 'exist') return_value(containers[ARG] !== undefined);

    if (containers[ARG] === undefined) return_error('CONTAINER DONT EXISTS');
    var container = containers[ARG];

    if (CMD === PUT) {
        if (VAL === undefined) containers[ARG][OPA] = true;
        else containers[ARG][OPA] = VAL;
        save_containers = true;
        exit();
    }

    if (CMD === GET) {
        if (OPA === 'br') return_value(container_bridge_address(container));
        if (OPA === 'reseller') return_value(container_reseller_user(container));
        if (OPA === 'host_ip') return_value(container_host_ip(container));
        if (OPA === 'host') return_value(container_host(container));

        // ip use_gsuite  
        return_optional_value(container[OPA]);
    }

    if (CMD == OUT) {
        output('C', ARG);
        Object.keys(container).forEach(function(j) {
            output(j, container[j]);
        });
        exit();
    }

    if (CMD === DEL) {
        delete containers[ARG];
        save_containers = true;
        exit();
    }
}

if (DAT === 'user') {

    if (CMD === NEW) {
        new_user(ARG);
        exit();
    }

    if (CMD === GET && OPA === 'exist') return_value(users[ARG] !== undefined);

    if (users[ARG] === undefined) return_error('USER DONT EXISTS');
    var user = users[ARG];

    if (CMD === PUT) {
        if (VAL === undefined) users[ARG][OPA] = true;
        else users[ARG][OPA] = VAL;
        save_users = true;
        exit();
    }

    if (CMD === GET) {
        
        if (OPA === 'password' && user.password === undefined) return_value('');
        if (OPA === 'uid') return_value(get_user_uid(user));

        return_optional_value(user[OPA]);
        exit();
    }

    if (CMD == OUT) {
        output('U', ARG);
        Object.keys(user).forEach(function(j) {
            output(j, user[j]);
        });
        exit();
    }

    if (CMD === DEL) {
        delete users[ARG];
        save_users = true;
        exit();
    }

}

if (DAT === 'host') {

    if (hosts[ARG] === undefined) return_error('HOST DONT EXISTS');
    var host = hosts[ARG];

    if (CMD === GET) {
        
        //allow undefined values
        if (OPA === 'host_ip' && host.host_ip === undefined) exit();
        if (OPA === 'hostnet' && host.hostnet === undefined) exit();
        
        return_optional_value(host[OPA]);
        exit();
    }

    if (CMD == OUT) {
        output('SC_HOSTNAME', ARG);
        Object.keys(host).forEach(function(j) {
            output('SC_' + j.toUpperCase(), host[j]);
        });
        exit();
    }
}

if (DAT === 'system') {
    if (CMD === CFG) {
        if (ARG === 'etc_hosts') system_etc_hosts();
        if (ARG === 'postfix_relaydomains') system_postfix_relaydomains();
        if (ARG === 'ssh_config') system_ssh_config();
        if (ARG === 'host_keys') system_host_keys();
        if (ARG === 'container_list') system_container_list();
        if (ARG === 'host_list') system_host_list();
        if (ARG === 'host_ip_list') system_host_ip_list();
        if (ARG === 'user_list') system_user_list();
        exit();
    }

}


return_error("EXIT on data.js EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);
