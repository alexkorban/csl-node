var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "create table vars (" +
            "var varchar(255) not null unique, " +
            "value json not null default '{}'::json)"
        )
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, "drop table if exists vars")
    ], callback);

};
