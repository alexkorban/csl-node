dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql """
            alter type event_type add value 'stop'
        """, ->
            db.runSql """
                alter type event_type add value 'move'
            """, ->
                db.runSql "begin", callback


exports.down = (db, callback) ->
    callback
