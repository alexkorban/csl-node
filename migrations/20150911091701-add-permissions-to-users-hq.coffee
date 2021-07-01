dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users_hq add permissions json default '{"projects": [], "reports": []}';
        update users_hq set permissions = '{"projects": "all", "reports": "all"}';
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users_hq drop permissions
    """, callback