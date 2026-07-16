#!/bin/node
"use strict";

const os = require("os");
const config = require("./cluster-config.js");

function usage() {
    throw new config.ClusterConfigError(
        "usage: cluster-config-cli.js {validate|sha256|hosts|v3safe} FILE | local FILE [HOSTNAME] | " +
        "verify FILE HOST_CONF HOSTS_JSON [HOSTNAME]");
}

function main(argv) {
    const command = argv[2];
    const filename = argv[3];
    if (!command || !filename) usage();

    if (command === "validate" || command === "sha256" || command === "hosts" ||
        command === "v3safe") {
        if (argv.length !== 4) usage();
        const parsed = config.readClusters(filename);
        if (command === "validate") console.log("sha256\t" + parsed.sha256);
        if (command === "sha256") console.log(parsed.sha256);
        if (command === "hosts") {
            parsed.records.forEach(function(record) { console.log(record.hostname); });
        }
        if (command === "v3safe") {
            config.assertLegacyRenderSafe(parsed);
            console.log(parsed.sha256);
        }
        return;
    }

    if (command === "verify") {
        if (argv.length < 6 || argv.length > 7) usage();
        console.log(config.verifyProjection(filename, argv[4], argv[5], argv[6] || os.hostname()));
        return;
    }

    if (command === "local") {
        if (argv.length < 4 || argv.length > 5) usage();
        const parsed = config.readClusters(filename);
        console.log(config.requireLocalHost(parsed.records, argv[4] || os.hostname()).clusterName);
        return;
    }

    usage();
}

try {
    main(process.argv);
} catch (error) {
    console.error("DATA-ERROR:", error.message);
    process.exit(113);
}
