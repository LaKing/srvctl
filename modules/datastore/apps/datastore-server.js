/*
 *  modules/datastore/apps/datastore-server.js — the well-known http daemon.
 *
 *  Standalone node process run as root by datastore-server.service (unit
 *  written by libs/httpserverlib.sh). Listens on port 1030 (all
 *  interfaces); haproxy forwards two internet-reachable paths here:
 *    /.well-known/srvctl/datastore/containers.json — public containers
 *        snapshot from /var/srvctl3/datastore
 *    /.well-known/pki-validation/<file> — ACME/CA validation files placed
 *        in /var/srvctl3/datastore/pki-validation/ by the haproxy module
 *  Any other request is answered 200 with an "INVALID URL" body.
 */

// Load modules to create a http server.
var http = require("http");
var fs = require("fs");
var path = require("path");
var url = require("url");

var DEFAULT_DATASTORE_DIR = "/var/srvctl3/datastore";
var DEFAULT_PKI_VALIDATION_DIR = "/var/srvctl3/datastore/pki-validation";
var DATASTORE_PATH = "/.well-known/srvctl/datastore/containers.json";
var storeModuleUrl = url.pathToFileURL(path.join(__dirname, "../lib/store.mjs")).href;

// store.mjs is ESM while this long-running daemon remains CommonJS. Dynamic
// import lets the endpoint share the storage engine's upgrade semantics rather
// than growing another copy of them here. Node caches the imported module.
function loadStoreModule() {
    return import(storeModuleUrl);
}

async function readContainersSnapshot(datastoreDir) {
    var storeModule = await loadStoreModule();
    var store = storeModule.createStore(datastoreDir, {
        git: false,
        readOnly: true,
    });
    return JSON.stringify(store.readAll("containers"), null, 2) + "\n";
}

function createHttpServer(options) {
    options = options || {};
    var datastoreDir = options.datastoreDir || DEFAULT_DATASTORE_DIR;
    // Keep the unrelated validation endpoint on its historical fixed path.
    var pkiValidationDir = options.pkiValidationDir || DEFAULT_PKI_VALIDATION_DIR;

    // Configure our HTTP server to respond with a file-read to all requests on the acme URL.
    return http.createServer(function(req, res) {
        // srvctl internal
        if (req.url === DATASTORE_PATH) {
            // readAll() is authoritative for every supported datastore state:
            // before migration it merges monolithic + per-entity (per-entity
            // wins), while .per-entity makes only entity files authoritative.
            readContainersSnapshot(datastoreDir).then(function(content) {
                res.writeHead(200, {
                    "Content-Type": "application/json"
                });
                console.log("CONTENT sent");
                res.end(content);
            }).catch(function(err) {
                console.error("CANNOT BUILD containers snapshot: " + err.message);
                res.writeHead(500, {
                    "Content-Type": "application/json"
                });
                res.end('{"error":"INVALID DATA"}\n');
            });

            return;
        }

        // domain validation
        if (req.url.substring(0, 27) === "/.well-known/pki-validation") {
            // FIXME(v4): path traversal — req.url is appended unsanitized, so a
            // crafted /.well-known/pki-validation/../../<path> request can read
            // files outside the pki-validation directory (process runs as root
            // and the path is internet-reachable via haproxy).
            var hash_file = pkiValidationDir + "/" + req.url.substring(28);
            fs.access(hash_file, fs.R_OK, function(err) {
                if (!err) {
                    fs.readFile(hash_file, function(err, data) {
                        if (err) return res.end("INVALID DATA");
                        var content = data.toString();
                        console.log("CONTENT sent");
                        res.end(content);
                    });
                } else {
                    console.log("CANNOT READ file");
                    res.end("CANNOT READ: " + hash_file);
                }
            });

            return;
        }

        // a default error
        res.writeHead(200, {
            "Content-Type": "application/json"
        });
        res.end("INVALID URL: " + req.url);
        console.log("INVALID URL: " + req.url);
    });
}

if (require.main === module) {
    var http_server = createHttpServer();
    http_server.listen(1030);
    console.log("Started datastore-server.js");
}

module.exports = {
    DATASTORE_PATH: DATASTORE_PATH,
    createHttpServer: createHttpServer,
    readContainersSnapshot: readContainersSnapshot,
};
