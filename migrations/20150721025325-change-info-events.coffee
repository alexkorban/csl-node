dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE info_event_type ADD VALUE 'error'", ->
            db.runSql "begin; alter table info_events alter user_id drop not null", callback


exports.down = (db, callback) ->
    db.runSql """
        alter table info_events alter user_id set not null
    """, callback

