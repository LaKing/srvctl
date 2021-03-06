(function() {


    var app = angular.module('app', ['ngSanitize','ui.bootstrap']);

    app.run(function($rootScope) {

        // rootscope functions and variables

        $rootScope.lock = false;

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


    app.controller('mainController', ['$scope', '$http', '$rootScope', 'socket', function($scope, $http, $rootScope, socket) {
        $scope.main = {};


        $scope.HOST = 'host';
        $scope.CONTAINER = 'container';
        $scope.SERVICE = 'service';
        $scope.USER = 'user';
        
        $scope.selected = 'host';        
        $scope.host = 'localhost';
        
        $scope.set = function(sel,set) {
            $scope.selected = sel;
            $scope[sel] = set;    
        };
        
        socket.on('main', function(main) {
            console.log(main);
            $scope.main = main;
        });
        
        $scope.terminal = 'Please wait.';
        socket.on('terminal', function(term) {
            $scope.terminal = '<pre>' + term + '</pre>';
            $rootScope.lock = false;
        });
        
        $scope.command = function(command) {
            if ($rootScope.lock) {
                alert("Please wait.");
                return;
            }
            $scope.terminal = '';
            $rootScope.lock = true;

            var cmd_json = {
                host: $scope.host,
                container: $scope.container,
                service: $scope.service,
                user: $scope.user,
                selected: $scope.selected,
                command: command
            };
            socket.emit('command', cmd_json);
        };
        
        $scope.command('srvctl status');
        
    }]);

})();
