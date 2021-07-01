dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table sessions alter column created_at set data type timestamp with time zone,
                             alter column updated_at set data type timestamp with time zone
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table sessions alter column created_at set data type timestamp without time zone,
                             alter column updated_at set data type timestamp without time zone
    """, callback
