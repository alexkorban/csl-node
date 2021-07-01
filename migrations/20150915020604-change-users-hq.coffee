dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users_hq alter permissions set not null
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users_hq alter permissions drop not null
    """, callback

