var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "alter table events alter id type bigint"),
        db.runSql.bind(db, "alter table overlays alter id type bigint"),
        db.runSql.bind(db, "alter table positions alter id type bigint"),
        db.runSql.bind(db, "alter table projects alter id type bigint"),
        db.runSql.bind(db, "alter table users alter id type bigint")
    ], callback);

};

exports.down = function(db, callback) {

};
