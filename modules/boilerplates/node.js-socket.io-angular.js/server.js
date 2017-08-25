#!/bin/node


const dev = true;
console.log("DEV: ", dev);


var fs = require("fs");
var http = require("http");
var https = require("https");
var express = require('express');

// https needs certificates
var options = {
    key: fs.readFileSync("key.pem"),
    cert: fs.readFileSync("crt.pem")
};

var app = express();


// update. We dont use basic auth, but rather a passpin based auth.
// xoclockapp.use(auth.connect(basic));


app.use(express.static('public'));
app.use(express.static('node_modules/angular'));
//app.use(express.static('node_modules/angular-ui-bootstrap/dist'));

var httpsServer = https.createServer(options, app);
var io = require('socket.io')(httpsServer, { wsEngine: 'ws' });

io.on('connection', function(socket){
  console.log('a user connected');

  socket.on('login', function(userdata){
    socket.user = userdata;
    
    if (dev) socket.user = {username: "dev", password: "developer"};
   
    console.log('user-login',socket.user);
	socket.emit("login-ok", socket.user);
  });


  socket.on('disconnect', function(){
    console.log('user disconnected');
  });
});

httpsServer.listen(443, function() {
    console.log("https server started on port " + 443);
});
