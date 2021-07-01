dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table projects rename boundary to download_boundary
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects rename download_boundary to boundary
    """, callback

