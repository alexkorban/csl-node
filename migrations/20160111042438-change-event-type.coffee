dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE event_type ADD VALUE 'concrete_movement'", callback


exports.down = (db, callback) ->
    callback
