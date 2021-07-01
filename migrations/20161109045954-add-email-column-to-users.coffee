dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users add email varchar
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users drop if exists email
    """, callback

