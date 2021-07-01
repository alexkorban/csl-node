dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users add truck_no varchar
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users drop truck_no
    """, callback

