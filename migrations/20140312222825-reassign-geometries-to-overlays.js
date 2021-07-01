var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "insert into overlays (name, project_id, display_order) select 'Hazards' as name, id as project_id, 100 as display_order from projects"),
        db.runSql.bind(db, "insert into overlays (name, project_id, display_order) select 'Boundary' as name, id as project_id, 0 as display_order from projects"),
        db.runSql.bind(db, "insert into overlays (name, project_id, display_order) select 'Fill' as name, id as project_id, 0 as display_order from projects"),
        db.runSql.bind(db, "alter table geometries drop constraint project_id_ref"),
        db.runSql.bind(db, "alter table geometries rename project_id to overlay_id"),
        db.runSql.bind(db, "update geometries set overlay_id = (select id from overlays where project_id = geometries.overlay_id and name = 'Hazards')"),
        db.runSql.bind(db, "alter table geometries " +
            "add constraint overlay_id_ref foreign key (overlay_id) references overlays")
    ], callback);

};

exports.down = function(db, callback) {

};
