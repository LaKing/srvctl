(function() {

	
    var app = angular.module('app', []);
    //var app = angular.module('app', ['ui.bootstrap']);

    app.run(function($rootScope) {

        // rootscope functions and variables
	$rootScope.page = "login";
	$rootScope.title = "log in";

	$rootScope.user = {};

        $rootScope.viewOnly = true;
        if (location.protocol === 'https:') $rootScope.viewOnly = false;

    });

    app.factory('socket', function($rootScope) {
        var socket = io.connect();
        return {
            on: function(eventName, callback) {
                socket.on(eventName, function() {
                    var args = arguments;
                    $rootScope.$apply(function() {
                        callback.apply(socket, args);
                    });
                });
            },
            emit: function(eventName, data, callback) {
                socket.emit(eventName, data, function() {
                    var args = arguments;
                    $rootScope.$apply(function() {
                        if (callback) {
                            callback.apply(socket, args);
                        }
                    });
                });
            }
        };
    });


    app.controller('loginController', ['$scope', '$http', '$rootScope', 'socket', function($scope, $http, $rootScope, socket) {
	console.log("loginController");
	$scope.user = {}
	$scope.user.username = "";
	$scope.user.password = "";

	$scope.login = function() {
		socket.emit("login",$scope.user);
	};

	socket.on("login-ok", function(data){
	   $rootScope.page = "main";
	   $rootScope.user = data;
	   $rootScope.title = user.username;
	});

    }]);

    app.controller('mainController', ['$scope', '$http', '$rootScope', 'socket', function($scope, $http, $rootScope, socket) {
	$scope.main = {};
	socket.on('main', function(data) {
            $scope.main = data;
        });

    }]);

})();

