var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'drop table if exists overlays'),
        db.runSql.bind(db, 'alter table site_overlay_files rename to overlays')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table overlays rename to site_overlay_files')
    ], callback);

};