dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update user_roles set properties = json_object_set_key(json_object_del_key(properties, 'does_signon')
                                               , 'belongs_to_cor', (properties->>'does_signon')::boolean);

    """, callback


exports.down = (db, callback) ->
    db.runSql """
        update user_roles set properties = json_object_set_key(json_object_del_key(properties, 'belongs_to_cor')
                                               , 'does_signon', (properties->>'belongs_to_cor')::boolean);
    """, callback

