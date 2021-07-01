dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table positions add column altitude double precision not null default 0,
        add column altitude_accuracy double precision not null default 0
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table positions drop if exists altitude,
        drop if exists altitude_accuracy
    """, callback

