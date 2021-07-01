dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        drop table if exists postgis.migrations
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        create table postgis.migrations (
            id integer primary key,
            name varchar not null,
            run_on timestamp without time zone not null
        )
    """, callback

