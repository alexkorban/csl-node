dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE info_event_type ADD VALUE 'app_stop'", callback


exports.down = (db, callback) ->
    callback
