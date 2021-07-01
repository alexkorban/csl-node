dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table positions add column accel json not null default '{"x": 0, "y": 0, "z": 0}'
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table positions drop if exists accel
    """, callback

