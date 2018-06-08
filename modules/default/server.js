#!/bin/node

var http = require('http');
var fs = require('fs');

html404 = fs.readFileSync('/var/www/html/404.html');

var server = http.createServer(function onRequest(req, res) {

    //logging the request
    console.log(req.headers.host, req.url, req.headers['user-agent'], req.headers['x-forwarded-for']);

    
    res.writeHead(404, {'Content-Type': 'text/html'});  
    res.write(html404);  
    res.end();

});
// Listen
server.listen(1282);
console.log("srvctl default-server started");
