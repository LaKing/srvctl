// Load modules to create a http server.
var http = require("http");
var fs = require('fs');

// Configure our HTTP server to respond with a file-read to all requests on the acme URL.
var http_server = http.createServer(function(req, res) {
    res.writeHead(200, {
        "Content-Type": "application/json"
    });
    if (req.url === "/.well-known/srvctl/datastore/containers.json") {

        var ch = req.url.substring(28);
        var file = '/var/srvctl3/datastore/containers.json';

        fs.access(file, fs.R_OK, function(err) {
            if (!err) {
                fs.readFile(file, function(err, data) {
                    if (err) return res.end("INVALID DATA");
                    var content = data.toString();
                    console.log("CONTENT: " + content);
                    res.end(content);
                });
            } else {
                console.log("CANNOT READ: " + ch);
                res.end("CANNOT READ: " + ch);
            }

        });

    } else {
        res.end("INVALID URL: " + req.url);
        console.log("INVALID URL: " + req.url);
    }
});

http_server.listen(1030);
console.log('Started datastore-server.js');