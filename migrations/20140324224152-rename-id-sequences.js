var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "alter sequence site_overlay_files_id_seq rename to overlays_id_seq"),
        db.runSql.bind(db, "alter table overlays alter id set default nextval('overlays_id_seq'::regclass)"),
        db.runSql.bind(db, "alter sequence restricted_areas_id_seq rename to geometries_id_seq"),
        db.runSql.bind(db, "alter table geometries alter id set default nextval('geometries_id_seq'::regclass)")
    ], callback);

};

exports.down = function(db, callback) {

};
