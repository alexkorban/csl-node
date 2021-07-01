dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table projects add properties json not null default '{}'
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects drop properties
    """, callback

