#!/bin/node

/*jshint esnext: true */

// regenerate users

function out(msg) {
    console.log(msg);
}

// includes
const fs = require('fs');
const datastore = require('../datastore/lib.js');
const password_lib = require('../password/lib.js');

const lablib = '../../lablib.js';
const msg = require(lablib).msg;
const ntc = require(lablib).ntc;
const err = require(lablib).err;
const get = require(lablib).get;
const run = require(lablib).run;
const rok = require(lablib).rok;
const exec_function = require(lablib).exec_function;

const execSync = require('child_process').execSync;
const CMD = process.argv[2];
// constatnts

const NOW = process.env.NOW;
const SRVCTL = process.env.SRVCTL;
const SC_DATASTORE_DIR = process.env.SC_DATASTORE_DIR;
const SC_COMPANY_DOMAIN = process.env.SC_COMPANY_DOMAIN;
const SC_ROOTCA_HOST = process.env.SC_ROOTCA_HOST;
const os = require('os');
const HOSTNAME = os.hostname();
const localhost = 'localhost';
const br = '\n';
const root = "root";
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
    console.error('main.js ERR:', msg);
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


//if (DAT === 'container') container = ARG;
//if (DAT === 'user') user = ARG;

/*


console.log("usershares");

/*
// a js based implementation
function crate_user_password(user) {
    
    var userdata = SC_DATASTORE_DIR + "/users/" + user;
    var passfile = userdata + "/.password";
    var password;
    if (fs.existsSync(passfile)) password = fs.readFileSync(passfile, 'utf8').trim();
    if (password === undefined) password = password_lib.get_password();
    if (password.length < 10) password = password_lib.get_password();
    
        
    fs.writeFileSync(passfile, password);
    
    msg("Password-update for user: " + user + " password: " + password);
    run("echo " + password + " | passwd " + user + " --stdin 2> /dev/null 1> /dev/null");
    run("echo " + password + " > $(getent passwd " + user + " | cut -f6 -d:)/.password");
   
}
*/

function create_user_ssh(user){
  // user is the username here
  
  var dir = SC_DATASTORE_DIR + "/users/" + user;
  if (!fs.existsSync(dir)) fs.mkdirSync(dir);
  fs.chmodSync(dir, 0600);

    /// the id_rsa (without prefix) will be placed in the users home directory.
    /// that means users have access to the keyfile.

    if (!fs.existsSync(dir + "/id_rsa")) {
        msg("Create datastore user id_rsa for " + user);
        var cmd1 = "ssh-keygen -t rsa -b 4096 -f " + SC_DATASTORE_DIR + "/users/" + user + "/id_rsa -N '' -C '" + user + "@" + SC_COMPANY_DOMAIN +" (id_rsa " + HOSTNAME + " " + NOW +")'";
        run(cmd1);      
    }
    
    /// the srvctl_id_rsa is used internally, in the srvctl-gui, in sshpiperd, and in the reseller-user structure.
    /// that means users do not have access to the keyfile, thus we can say they are save and wont be compromised.
    
    if (!fs.existsSync(dir + "/srvctl_id_rsa")) {
        msg("Create datastore srvctl_id_rsa for " + user);
        var cmd2 = "ssh-keygen -t rsa -b 4096 -f " + SC_DATASTORE_DIR + "/users/" + user + "/srvctl_id_rsa -N '' -C '" + user + "@" + SC_COMPANY_DOMAIN +" (srvctl " + HOSTNAME + " " + NOW +")'";
        run(cmd2);      
    }
        
    var home = get("getent passwd " + user).split(':')[5];
    
    if (!fs.existsSync(home + "/.ssh/id_rsa")) {
        run("mkdir -p " + home + "/.ssh");
        run("cat " + SC_DATASTORE_DIR + "/users/" + user + "/id_rsa > " + home + "/.ssh/id_rsa");
        run("cat " + SC_DATASTORE_DIR + "/users/" + user + "/id_rsa.pub > " + home + "/.ssh/id_rsa.pub");
        
        run("chown -R " + user + ":" + user + " " + home + "/.ssh");
        run("chmod -R 600 " + home + "/.ssh");
        run("chmod 700 " + home + "/.ssh");
    }
    
    if (users[user].reseller_id === undefined && users[user].reseller !== undefined) {
        var reseller = users[user].reseller;
        if (reseller === root) return;
        if (!fs.existsSync(SC_DATASTORE_DIR + "/users/" + user + "/reseller_id_rsa.pub")) {
            run("ln -s ../" + reseller + "/id_rsa.pub " + SC_DATASTORE_DIR + "/users/" + user + "/reseller_id_rsa.pub");
            run("ln -s ../" + reseller + "/srvctl_id_rsa.pub " + SC_DATASTORE_DIR + "/users/" + user + "/srvctl_reseller_id_rsa.pub");
        }
    }

}

function create_user_client_cert(user) {
    
    var home = get("getent passwd " + user).split(':')[5];
    var certfile = home + "/" + user + "@" + SC_COMPANY_DOMAIN + ".p12";
        
    if (fs.existsSync(certfile)) return;
    
    msg("create_user_client_cert for " + user);
    
    if (SC_ROOTCA_HOST === HOSTNAME) {
        exec_function("create_ca_certificate client usernet " +user);
    } 
    
    //if (SC_ROOTCA_HOST !== HOSTNAME) {
    //   run("timeout 1 ssh " + SC_ROOTCA_HOST + " srvctl exec-function create_ca_certificate client usernet " + user);
    //}
    
    if (!fs.existsSync(SC_DATASTORE_DIR + "/users/" +user +"/" + user + "@" + SC_COMPANY_DOMAIN + ".p12")) {
        err("no client cert for " + user);
        return;
    }
    
    run("cat " + SC_DATASTORE_DIR + "/users/" + user + "/" + user + "@" + SC_COMPANY_DOMAIN + ".p12 > " + home  + "/" + user + "@" + SC_COMPANY_DOMAIN + ".p12");
    
    run("chown " + user + ":" + user + " " + home + "/" + user + "@" + SC_COMPANY_DOMAIN + ".p12");
    run("chmod 400 " + home + "/" + user + "@" + SC_COMPANY_DOMAIN + ".p12");
        
    msg("Placed p12 client certificate in home folder for " + user);
    
}

var mounts = get("mount");

function make_share(u, c) {
    msg("Match " + c + " to " + u );
    var getent = get("getent passwd " + u);
    //if (getent === undefined) return;
    var dir = getent.split(':')[5] + '/' + c;
    var ve_root_uid = datastore.container_uid(containers[c]);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir);
    var host = datastore.container_host(containers[c]);
    //  var source_path = "/srv/" + c + "/rootfs";
    //  if (host !== HOSTNAME) 
    var source_path = "/var/srvctl3/nfs/" + host + "/srv/" + c + "/rootfs";
    if (!fs.existsSync(dir + '/bindfs')) fs.mkdirSync(dir + '/bindfs');
    if (fs.existsSync(source_path) && mounts.indexOf(source_path + " on " + dir + "/bindfs type fuse") !== -1) return;
 // var xc = "bindfs -m " + u + " " + source_path + " " + dir + "/bindfs";
    var xc = "bindfs --mirror=" + u + " --create-for-user=" + ve_root_uid + " --create-for-group=" + ve_root_uid + " "+ source_path + " " + dir + "/bindfs";
    run(xc);

}

msg("check users");
Object.keys(users).forEach(function(u) {
    if (u === root) return;
    if (!rok("id " + u)) {
        if (users[u].uid === undefined) return err("No UID for " + u);
        if (users[u].name === undefined) users[u].name = u;
        if (users[u].reseller === undefined) run("adduser -U -c '" + users[u].name + "' -u " + users[u].uid + " " + u);
        else run("adduser -U -c '" + users[u].reseller + ' - ' + users[u].name + "' -u " + users[u].uid + " " + u);
    }
        //exec_function("create_user_ssh " + u + ' ' + users[u].reseller);
        create_user_ssh(u);
        //exec_function("create_user_client_cert " + u);
        create_user_client_cert(u);
    

});

msg("users share's");
Object.keys(containers).forEach(function(c) {
    if (containers[c].user === root) return;
    make_share(containers[c].user, c);
});
        msg("SC_ROOTCA_HOST:" + SC_ROOTCA_HOST);

exit();

