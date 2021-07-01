dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE permission_type ADD VALUE 'signon'", ->
            db.runSql "begin", callback

exports.down = (db, callback) ->
    callback
