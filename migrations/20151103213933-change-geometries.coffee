dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table geometries add deleted_at timestamp with time zone not null default '-infinity';
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table geometries drop deleted_at
    """, callback

