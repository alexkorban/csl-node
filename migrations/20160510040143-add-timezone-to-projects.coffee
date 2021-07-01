dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table projects add timezone varchar not null default 'Australia/NSW';
        alter table projects alter timezone drop default
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects drop if exists timezone
    """, callback

