dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "ALTER TYPE event_type ADD VALUE 'upload'", ->
            db.runSql "begin", callback
#    commit;
#    ALTER TYPE event_type ADD VALUE 'upload';
#    begin;

exports.down = (db, callback) ->
    db.runSql """
    """, callback

