#!/bin/node

/*jshint esnext: true */

const CMD = process.argv[2];
const DAT = process.argv[3];
const ARG = process.argv[4];
const OPA = process.argv[5];


function return_value(msg) {
    console.log(msg);
    process.exit(0);
}

function return_error(msg) {
    console.error('ERROR', msg);
    process.exit(10);
}

if (CMD === undefined) return_error("MISSING CMD ARGUMENT");
if (DAT === undefined) return_error("MISSING DAT ARGUMENT");
//if (ARG === undefined) return_error("MISSING ARG ARGUMENT");

// OPA is optional

const SC_DATA_FILE = '/etc/srvctl/' + DAT + '.json';

var fs = require('fs');
var main = {};
try {

    main = JSON.parse(fs.readFileSync(SC_DATA_FILE));

} catch (err) {
    return_error('READFILE ' + SC_DATA_FILE);
}

//process.exit(0);

if (CMD == "get") return_value("Its all good now. relax");

return_error("EXIT on EOF :: CMD:" + CMD + " ARG:" + ARG + " OPA:" + OPA);
