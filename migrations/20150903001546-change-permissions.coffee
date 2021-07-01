dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table permissions add updated_at timestamp with time zone not null default now();
        update permissions set updated_at = created_at;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table permissions drop updated_at
    """, callback

