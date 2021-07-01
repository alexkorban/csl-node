dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table geometries add user_id bigint references users

    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table geometries drop if exists user_id
    """, callback

