#!/bin/node

/*jshint esnext: true */

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';
const SC_USERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/users.json';
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';
const SC_DATASTORE_RO = process.env.SC_DATASTORE_RO;
const dot = '.';
const root = 'root';
const br = '\n';

if (process.env.SC_USER !== undefined) SC_USER = process.env.SC_USER;
else SC_USER = process.env.USER;

if (process.env.NOW !== undefined) NOW = process.env.NOW;
else NOW = new Date().toISOString();


if (process.env.SC_ON_HS !== undefined) ON_HS = process.env.ON_HS;
else ON_HS = false;
const SC_ON_HS = ON_HS;

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const os =  require('os');
const HOSTNAME = os.hostname();
const SC_HOSTNET = Number(process.env.SC_HOSTNET);
const SC_CLUSTERNAME = process.env.SC_CLUSTERNAME;


// includes
var fs = require('fs');

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
    process.exitCode = 111;
    process.exit(111);
}

function return_value(msg) {
    if (msg === undefined || msg === '') process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function load_hosts() {
    try {
        return JSON.parse(fs.readFileSync(SC_HOSTS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_HOSTS_DATA_FILE + ' ' + err);
    }
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
        return_error('READFILE ' + SC_USERS_DATA_FILE + ' ' + err);
    }
}

var users = load_users();
exports.users = users;

function load_resellers() {
    var resellers = {};
    Object.keys(users).forEach(function(i) {
        if (users[i].reseller_id !== undefined)
            resellers[i] = users[i];
    });
    return resellers;    
}

var resellers = load_resellers();
exports.resellers = resellers;

function load_containers() {
    try {
        return JSON.parse(fs.readFileSync(SC_CONTAINERS_DATA_FILE));
    } catch (err) {
        return_error('READFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
    }
}

var containers = load_containers();
exports.containers = containers;

function write_users() {
    if (SC_DATASTORE_RO) return_error("Readonly datastore.");
    else
        try {
            fs.writeFile(SC_USERS_DATA_FILE, JSON.stringify(users, null, 2), function(err) {
                if (err) return_error('WRITEFILE ' + err);
                else console.log('[ OK ] users.json');
            });
        } catch (err) {
            return_error('WRITEFILE ' + SC_USERS_DATA_FILE + ' ' + err);
        }
}

exports.write_users = function() {
    write_users();
};

function write_containers() {
    if (SC_DATASTORE_RO) return_error("Readonly datastore.");
    else
        try {
            fs.writeFile(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2), function(err) {
                if (err) return_error('WRITEFILE ' + err);
                else console.log('[ OK ] containers.json');
            });
        } catch (err) {
            return_error('WRITEFILE ' + SC_CONTAINERS_DATA_FILE + ' ' + err);
        }
}

exports.write_containers = function() {
    write_containers();
};

function container_uid(container) {
    var cipa = container.ip.split(dot);
    return 65536 * ((Number(cipa[2]) * 255) + Number(cipa[3]));
}

exports.container_uid = function(container) {
    return container_uid(container);
};

function container_bridge_address(container) {
    var cipa = container.ip.split(dot);
    return '10' + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + 'x';
}

exports.container_bridge_address = function(container) {
    return container_bridge_address(container);
};

function container_bridge_host_ip(container) {
    var cipa = container.ip.split(dot);
    return '10' + dot + Number(cipa[1]) + dot + Number(cipa[2]) + dot + '1';
}

exports.container_bridge_host_ip = function(container) {
    return container_bridge_host_ip(container);
};

function container_hostnet(container) {
    return container.ip.split(dot)[1];
}

exports.container_hostnet = function(container) {
    return container_hostnet(container);
};


function container_host(container) {
    var hostnet = container_hostnet(container);
    var ret;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet)
            ret = i;
    });
    return ret;
}

exports.container_host = function(container) {
    return container_host(container);
};

function container_host_ip(container) {
    var hostnet = container_hostnet(container);
    var ret = "ERROR datastore/lib.js: container_host_ip not found";
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].hostnet == hostnet)
            ret = hosts[i].host_ip;
    });
    return ret;
}

exports.container_host_ip = function(container) {
    return container_host_ip(container);
};

function container_reseller_user(container) {

    return container;
}

exports.container_reseller_user = function(container) {
    return container_reseller_user(container);
};

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

function container_http_port(container) {
    if (container.http_port) return container.http_port;
    else return 80;
}

exports.container_http_port = function(container) {
    return container_http_port(container);
};


function container_https_port(container) {
    if (container.https_port) return container.https_port;
    else return 443;
}

exports.container_https_port = function(container) {
    return container_https_port(container);
};


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

exports.get_user_uid = function(u) {
    return get_user_uid(u);
};

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
    var c = find_next_cip_for_container_on_network('10.' + a + dot + b + dot + 'x');

    return '10.' + a + dot + b + dot + c;
}

function new_user(username) {
    if (users[username] !== undefined) return_error('USER EXISTS');
    var user = {};
    user.added_by_username = SC_USER;
    user.added_on_datestamp = NOW;

    
    if (users[SC_USER].reseller_id === undefined) return_error('MISSING RESELLER_ID');

    user.reseller = SC_USER;
    user.user_id = get_next_user_id();
    users[username] = user;

    get_user_uid(username);
}

exports.new_user = function(username) {
    new_user(username);
};

function new_reseller(username) {
    if (users[username] !== undefined) return_error('USER EXISTS');
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

exports.new_reseller = function(username) {
    new_reseller(username);
};

function new_container(C, T) {

    if (containers[C] !== undefined) return_error('CONTAINER EXISTS');

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

exports.new_container = function(C, T) {
    new_container(C, T);
};

function cluster_etc_hosts() {
    var str = '';
    str += "## srvctl generated" + br;
    str += "127.0.0.1    localhost.localdomain localhost" + br;
    str += "::1    localhost6.localdomain6 localhost6" + br;
    str += "## hosts" + br;
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip) str += hosts[i].host_ip + '    ' + i + br;
        if (hosts[i].hostnet) str += '10.15.'+hosts[i].hostnet+'.0    ' + i.split('.')[0] + br;
    });
    str += "## containers" + br;
    Object.keys(containers).forEach(function(i) {
        if (containers[i].ip) {
            str += containers[i].ip + '    ' + i + br;
            if (containers["mail." + i] === undefined) str += containers[i].ip + '    mail.' + i + br;
        }
    });
    fs.writeFile('/etc/hosts', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] etc-hosts');
    });
}

exports.cluster_etc_hosts = function() {
    cluster_etc_hosts();
};

function cluster_postfix_relaydomains() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        str += i + ' #' + br;
    });
    fs.writeFile('/etc/postfix/relaydomains', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] postfix relaydomains');
    });
}

exports.cluster_postfix_relaydomains = function() {
    cluster_postfix_relaydomains();
};


function cluster_host_keys() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        Object.keys(hosts[i]).forEach(function(j) {
            if (j.substring(0, 8) === 'host-key') str += hosts[i][j] + br;
        });
    });
    Object.keys(containers).forEach(function(i) {
        Object.keys(containers[i]).forEach(function(j) {
            if (j.substring(0, 8) === 'host-key') str += containers[i][j] + br;
        });
    });
    fs.writeFile('/etc/ssh/ssh_known_hosts', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else console.log('[ OK ] ssh known_hosts');
    });
}

exports.cluster_host_keys = function() {
    cluster_host_keys();
};

function cluster_user_list() {
    var str = '';
    Object.keys(users).forEach(function(i) {
        str += i + ' ';
    });
    return str;
}

exports.cluster_user_list = function() {
    return cluster_user_list();
};


function cluster_container_list() {
    var str = '';
    Object.keys(containers).forEach(function(i) {
        str += i + ' ';
    });
    return str;
}

exports.cluster_container_list = function() {
    return cluster_container_list();
};

function user_container_list() {
    var str = '';
    Object.keys(containers).forEach(function(i) {
        if (containers[i].user === SC_USER) str += i + ' ';
        else if (users[containers[i].user].reseller === SC_USER) str += i + ' ';
    });
    return str;
}

exports.user_container_list = function() {
    return user_container_list();
};

function cluster_host_list() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        str += i + ' ';
    });
    return str;
}

exports.cluster_host_list = function() {
    return cluster_host_list();
};

function cluster_host_ip_list() {
    var str = '';
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_ip !== undefined) str += hosts[i].host_ip + ' ';
    });
    return str;
}

exports.cluster_host_ip_list = function() {
    return cluster_host_ip_list();
};


/*
exports.# = function() {
    return #();
};
*/
