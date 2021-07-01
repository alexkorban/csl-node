dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create index events_on_user_id_created_at on events(user_id, created_at)
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop index if exists events_on_user_id_created_at
    """, callback

