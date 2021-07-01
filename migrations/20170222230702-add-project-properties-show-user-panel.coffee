dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update projects set properties = json_object_set_key(properties, 'show_users_panel', true);
    """, callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

