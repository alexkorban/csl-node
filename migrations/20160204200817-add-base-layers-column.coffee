dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table base_layers add drone_image bool not null default false
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table base_layers drop drone_image
    """, callback

