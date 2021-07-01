dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql """
            alter type permission_type add value 'configure_beacons'
        """, ->
            db.runSql "begin", callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

