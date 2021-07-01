dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update users_hq set email = lower(email)
    """, callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

