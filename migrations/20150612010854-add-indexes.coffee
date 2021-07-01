dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        drop index if exists positions_on_user_id_created_at;

        create index geometries_on_overlay_id on geometries(overlay_id);
        create index geometries_on_geometry on geometries using gist(geometry);

        create index positions_on_created_at on positions(created_at);
        create index positions_on_user_id on positions(user_id);

        create index events_on_user_id on events(user_id);
        create index events_on_project_id on events(project_id);
        create index events_on_geometry_id on events(geometry_id);
        create index events_on_created_at on events(created_at);
        create index events_on_type on events(type);

        create index info_events_on_type on info_events(type);
        create index info_events_on_user_id on info_events(user_id);
        create index info_events_on_project_id on info_events(project_id);
    """, callback


exports.down = (db, callback) ->
    db.runSql """

    """, callback

