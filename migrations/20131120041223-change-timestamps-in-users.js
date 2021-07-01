var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    db.runSql("select 1;", callback);
};

exports.down = function(db, callback) {
    db.runSql("select 1;", callback);
};
