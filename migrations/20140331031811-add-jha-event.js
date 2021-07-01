var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    // explicitly get out of the transaction to be able to alter type
    async.series([
        db.runSql.bind(db, "commit"),
        db.runSql.bind(db, "alter type event_type add value 'jha'"),
        db.runSql.bind(db, "begin")
    ], callback);

};

exports.down = function(db, callback) {

};
