#!/bin/node

/*jshint esnext: true */

function out(msg) {
    console.log(msg);
}

// includes
var fs = require('fs');
var datastore = require('../datastore/lib.js');
const execSync = require('child_process').execSync;

const CMD = process.argv[2];
// constatnts

const SC_CONTAINERS_DATA_FILE = process.env.SC_DATASTORE_DIR + '/containers.json';
const SC_CONTAINERS_CERT_DIR = process.env.SC_DATASTORE_DIR + '/cert';
const SC_INSTALL_DIR = process.env.SC_INSTALL_DIR;

const SRVCTL = process.env.SRVCTL;
const SC_ROOT = process.env.SC_ROOT;
const HOSTNAME = process.env.HOSTNAME;
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

var le_dirs = fs.readdirSync("/etc/letsencrypt/live");

function get_le_dir(domain) {
    var le_dir = 'undefined';
    le_dirs.forEach(dir => {
        if (dir.substring(0, domain.length + 4) === 'www.' + domain) le_dir = dir;
        if (dir.substring(0, domain.length) === domain) le_dir = dir;
    });
    return le_dir;
}

function deploy(le_dir,domain) {
     
    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";
    var fullchain_pem = "/etc/letsencrypt/live/" + le_dir + "/fullchain.pem";
    var privkey_pem = "/etc/letsencrypt/live/" + le_dir + "/privkey.pem";
    var ca_pem = "/etc/letsencrypt/ca.pem";
     
    var privkey = fs.readFileSync(privkey_pem, 'UTF8');
    var fullchain = fs.readFileSync(fullchain_pem, 'UTF8');
    var ca = fs.readFileSync(ca_pem, 'UTF8');
    
    var pem = privkey + br + fullchain + br + ca + br;
    
    fs.writeFileSync(SC_CONTAINERS_CERT_DIR + '/' + domain + '.pem', pem);
}


function run_domain(domain) {
    
    var cert_file = SC_CONTAINERS_CERT_DIR + "/" + domain + ".pem";
    if (fs.existsSync(cert_file)) {
        if (execSync('openssl x509 -checkend 604800 -noout -in ' + cert_file)) return;
    }
    
    var le_dir = get_le_dir(domain);
    var cert_pem = "/etc/letsencrypt/live/" + le_dir + "/cert.pem";

    if (fs.existsSync(cert_pem)) {
        if (execSync('openssl x509 -checkend 604800 -noout -in ' + cert_pem)) {
            deploy(le_dir,domain);
            return;
        }
    }
    
    // we can check against HOSTNAME if a reverse address is set, but since it is not mandatory ...
    //if (containers[domain].dns_scan.A[hosts[HOSTNAME].host_ip] === undefined) return; 
    
    console.log("Certificate required for " + domain);
    var cmd = "letsencrypt certonly --non-interactive --agree-tos --keep-until-expiring --expand --webroot --webroot-path /var/acme/ -d " + domain + " -d www." + domain + " >> /srv/" + domain + "/letsencrypt.log";
    console.log(cmd);
    try {
        execSync(cmd);
    } catch(err) {
        console.log("Exiting letsencrypt-srvctl process loop due to a failure.");
        process.exit(0);
        return;
    }
    
    console.log("success");  
    
    le_dir = get_le_dir(domain);
    deploy(le_dir,domain);
    
}

function main() {
    Object.keys(containers).forEach(function(i) {
        if ((i.substr(i.length - 6) !== '.devel') && (i.substr(i.length - 6) !== '-devel') && (i.substr(i.length - 6) !== '.local') && (i.substr(i.length - 6) !== '-local') && (i.substring(0, 5) !== 'mail.'))
            run_domain(i);
    });
}

main();

process.exitCode = 0;

process.on('exit', function() {
    fs.writeFileSync(SC_CONTAINERS_DATA_FILE, JSON.stringify(containers, null, 2));
});

exit();
