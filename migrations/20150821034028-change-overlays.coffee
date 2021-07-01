dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table overlays add is_restricted boolean not null default false
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table overlays drop is_restricted
    """, callback

