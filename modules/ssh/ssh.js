#!/bin/node

/*srvctl */

function out(msg) {
    console.log(msg);
}

// includes
const fs = require('fs');
const datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;

const lablib = '../../lablib.js';
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;
const exec_function = require(lablib).exec_function;

const os =  require('os');
const HOSTNAME = os.hostname();

const CMD = process.argv[2];
// constatnts
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;

const SC_HOSTS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/hosts.json';
const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;

const localhost = 'localhost';
const br = '\n';
process.exitCode = 99;

function exit() {
    process.exitCode = 0;
}

function return_value(msg) {
    if (msg === undefined || msg === '') process.exitCode = 100;
    else {
        console.log(msg);
        process.exitCode = 0;
    }
}

function return_error(msg) {
    console.error('DATA-ERROR:', msg);
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
var user = '';
var container = '';

var TrustedHosts = '';
var SigningTable = '';
var KeyTable = '';

TrustedHosts += '127.0.0.1' + br;
TrustedHosts += '::1' + br;
TrustedHosts += '10.0.0.0/8' + br;

function copy_user_key(c,u) {
    if (u === 'root') return;
    
    var i;

    var dir = '/var/srvctl3/share/containers/' + c;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    
    dir = SC_DATASTORE_DIR + "/users/" + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    
    dir = '/var/srvctl3/share/containers/' + c + '/users';
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }
    dir = '/var/srvctl3/share/containers/' + c + '/users/' + u;
    if (!fs.existsSync(dir)) {
        fs.mkdirSync(dir);
    }

    var files = fs.readdirSync(SC_DATASTORE_DIR + "/users/" + u);
 
    var pub;
    for (i = 0; i < files.length; i++) { 
        if (files[i].split('.')[1] === 'pub' || files[i].split('.')[1] === 'hash') {
            pub = fs.readFileSync(SC_DATASTORE_DIR + "/users/" + u + "/" + files[i]);
            fs.writeFileSync(dir + '/' + u + '-' + files[i], pub);
        }
    }
}

function remake_ssh_keys(c) {
    if (containers[c].user === undefined) return;
    
    // primary user
    copy_user_key(c,containers[c].user);
    
    // other users (developers, guests, people that are allowed to have root access)
    if (containers[c].users !== undefined) {   
        for (var i = 0; i < containers[c].users.length; i++) { 
            copy_user_key(c,containers[c].users[i]);
        }
    }
    
    // reseller
    if (users[containers[c].user] === undefined) return;
    if (users[containers[c].user].reseller === undefined) return;
    copy_user_key(c,users[containers[c].user].reseller);
    
}

function user_keys() {
    Object.keys(containers).forEach(function(c) {
            remake_ssh_keys(c);
    });
}

function ssh_config() {
    var str = '## ssh_config' + br;
        str += "Host localhost" + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "" + br;
        
        str += "Host 127.0.0.1" + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "" + br;
    
    Object.keys(hosts).forEach(function(i) {
        str += "Host " + i + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "" + br;
        
        str += "Host " + i.split('.')[0] + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "" + br;
        
    });
    fs.writeFile('/etc/ssh/ssh_config.d/srvctl-chosts.conf', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else msg('ssh srvctl-hosts.conf');
    });
    
    str = '';
    Object.keys(containers).forEach(function(i) {
        str += "Host " + i + br;
        str += "User root" + br;
        str += "StrictHostKeyChecking no" + br;
        str += "UserKnownHostsFile /var/srvctl3/ssh/known_hosts" + br;
        str += "UserKnownHostsFile /dev/null" + br;

        str += "" + br;
    });
    fs.writeFile('/etc/ssh/ssh_config.d/srvctl-containers.conf', str, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else msg('ssh srvctl-containers.conf');
    });
}

// for known hosts

function scan_host_keys() {
    Object.keys(hosts).forEach(function(i) {
        if (check_host_keys(hosts,i)) fs.writeFileSync(SC_HOSTS_DATA_FILE, JSON.stringify(hosts, null, 2));
    }); 
    Object.keys(containers).forEach(function(i) {
        if (check_host_keys(containers,i)) fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
    }); 
}

function check_host_keys(data, i) {
    if (data[i].host_key === undefined) {        
        try {
            var result = execSync("ssh-keyscan -t rsa -T 1 " + i +" 2> /tmp/srvctl-host-key-scan");
            data[i].host_key = result.toString().slice(0,-1).split(' ')[2];
        } catch(err) {
            if (err) console.log(err);
            if (err) return false;
        }
        return true;
    }
}

function make_host_keys(){
    var keys ='## ' + SRVCTL + ' generated' +br;
    
    Object.keys(hosts).forEach(function(i) {
        if (hosts[i].host_key !== undefined)
        { 
            keys += i + " ssh-rsa " + hosts[i].host_key + br;
            keys += hosts[i].host_ip + " ssh-rsa " + hosts[i].host_key + br;
            keys += i.split('.')[0] + " ssh-rsa " + hosts[i].host_key + br;
            keys += "10.15." + hosts[i].hostnet + "." + hosts[i].hostnet + " ssh-rsa " + hosts[i].host_key + br;
            keys += br;
        }
    });
    Object.keys(containers).forEach(function(i) {
        if (containers[i].host_key !== undefined)
        { 
            keys += i + " ssh-rsa " + containers[i].host_key + br;
            keys += containers[i].ip + " ssh-rsa " + containers[i].host_key + br + br;
        }        
    });       
    
    fs.writeFile('/var/srvctl3/share/common/known_hosts', keys, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else msg('ssh share/common/known_hosts');
    });
    
    // in addition, localhost
    if (hosts[HOSTNAME])
    if (hosts[HOSTNAME].host_key !== undefined)
    { 
        keys += "localhost ssh-rsa " + hosts[HOSTNAME].host_key + br;
        keys += "127.0.0.1 ssh-rsa " + hosts[HOSTNAME].host_key + br;
    }
    
    fs.writeFile('/var/srvctl3/ssh/known_hosts', keys, function(err) {
        if (err) return_error('WRITEFILE ' + err);
        else msg('ssh ssh/known_hosts');
    });
}

ssh_config();

scan_host_keys();
make_host_keys();

user_keys();

process.exitCode = 0;

process.on('exit', function() {
    msg('ssh configuration done');
});

exit();
