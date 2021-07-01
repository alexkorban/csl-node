var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'users', 'company', 'string'),
        db.addColumn.bind(db, 'users', 'role', 'string')
    ], callback);

};

exports.down = function(db, callback) {

};
