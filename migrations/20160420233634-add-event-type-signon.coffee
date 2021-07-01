dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE event_type ADD VALUE 'signon'", ->
            db.runSql "begin", callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

