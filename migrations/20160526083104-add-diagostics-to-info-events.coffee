dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql """
            alter type info_event_type add value 'diagnostics'
        """, ->
            db.runSql "begin", callback

exports.down = (db, callback) ->
    db.runSql """

    """, callback

