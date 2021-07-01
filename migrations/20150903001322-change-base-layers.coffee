dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table base_layers add updated_at timestamp with time zone not null default now();
        update base_layers set updated_at = created_at;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table base_layers drop updated_at
    """, callback

