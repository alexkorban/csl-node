dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table overlays add deleted_at timestamp with time zone not null default '-infinity'
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table overlays drop deleted_at
    """, callback

