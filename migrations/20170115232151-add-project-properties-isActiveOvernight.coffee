dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update projects set properties = json_object_set_key(properties, 'is_active_overnight', false);
    """, callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

