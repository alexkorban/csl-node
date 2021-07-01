var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "select 1")
    ], callback);

};

exports.down = function(db, callback) {

};
