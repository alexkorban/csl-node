dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users add truck_wheel_count int not null default 0
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users drop truck_wheel_count
    """, callback

