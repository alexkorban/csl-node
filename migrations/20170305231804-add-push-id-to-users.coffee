dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users add push_id varchar unique
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users drop push_id
    """, callback

