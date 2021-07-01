dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create index positions_on_user_id_created_at on positions(user_id, created_at)
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop index if exists positions_on_user_id_created_at
    """, callback

