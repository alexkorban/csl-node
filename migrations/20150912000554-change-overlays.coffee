dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create unique index ensure_single_boundary on overlays (project_id, is_boundary)
        where is_boundary = true;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop index if exists ensure_single_boundary
    """, callback

