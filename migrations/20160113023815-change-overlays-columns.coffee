dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update overlays set properties = json_object_set_key(properties, 'is_restricted', true) where is_restricted;
        update overlays set properties = json_object_set_key(properties, 'is_boundary', true) where is_boundary;
        alter table overlays drop is_restricted;
        alter table overlays drop is_boundary;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table overlays add is_restricted bool not null default false;
        alter table overlays add is_boundary bool not null default false;
        update overlays set is_restricted = true where properties->>'is_restricted';
        update overlays set is_boundary = true where properties->>'is_boundary';
    """, callback

