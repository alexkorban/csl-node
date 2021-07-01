dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table base_layers add display_order int not null default 0
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table base_layers drop display_order
    """, callback

