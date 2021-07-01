var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'drop table if exists geometries'),
        db.runSql.bind(db, 'alter table restricted_areas rename to geometries')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table geometries rename to restricted_areas')
    ], callback);

};
