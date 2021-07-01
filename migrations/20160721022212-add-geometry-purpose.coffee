dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update geometries set properties = json_object_set_key(properties, 'purpose', 'none'::text) where GeometryType(geometry) = 'POLYGON';
    """, callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

