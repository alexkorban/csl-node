dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE permission_type ADD VALUE 'extended_hours'", ->
            db.runSql "begin", callback

exports.down = (db, callback) ->
    callback
