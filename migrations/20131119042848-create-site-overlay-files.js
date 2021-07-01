var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.createTable("site_overlay_files", {
        ifNotExists: true,
        columns: {
            id: {type: "bigint", primaryKey: true, autoIncrement: true},
            name: {type: "string", notNull: true},
            bbox: {type: "box2d", notNull: true},
            convex_hull: {type: "geometry(POLYGON, 4326)"},
            created_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")},
            updated_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")}
        }
    }, addFunction);

    function addFunction(err) {
        if (err) { callback(err); return; }

        db.runSql("create or replace function site_overlays_with_point_in_bbox(lon float, lat float)" +
            "returns setof site_overlay_files as '" +
            "select * from site_overlay_files where ST_Contains(bbox, ST_Point(lon, lat));" +
            "' language 'sql';", callback);
    }

    //{"type":"Polygon","coordinates":[[[152.967264,-30.642994],[152.967264,-30.461819],[153.018372,-30.4.
    //    .61819],[153.018372,-30.642994],[152.967264,-30.642994]]]}
};

exports.down = function(db, callback) {
    db.runSql("drop function if exists site_overlays_with_point_in_bbox(float, float)"), function(err) {
        if (err) { callback(err); return; }
        db.dropTable("site_overlay_files", callback);
    }
};
