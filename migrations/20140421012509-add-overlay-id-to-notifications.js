var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "alter table notifications " +
            "add overlay_id bigint"),
        db.runSql.bind(db, "update notifications " +
            "set overlay_id = (select id from overlays where project_id = notifications.project_id limit 1)"),
        db.runSql.bind(db, "alter table notifications " +
            "alter overlay_id set not null"),
        db.runSql.bind(db, "alter table notifications " +
            "add constraint overlay_id_ref foreign key (overlay_id) references overlays")
    ], callback);

};

exports.down = function(db, callback) {
//    async.series([
//        db.runSql.bind(db, "drop table if exists vars")
//    ], callback);

};
