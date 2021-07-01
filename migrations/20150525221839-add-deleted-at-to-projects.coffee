dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table projects
        add deleted_at timestamp with time zone not null default '-infinity',
        drop if exists is_active,
        drop if exists folder
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects
        drop if exists deleted_at,
        add is_active boolean not null default true,
        add folder varchar(255) not null default 'unknown'
    """, callback

