dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        delete from users_projects;
        alter table users_projects alter synced_at type timestamp with time zone;
        insert into users_projects (user_id, project_id, synced_at)
            select user_id, project_id,
                last(created_at order by created_at)
            from positions
            group by user_id, project_id;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users_projects alter synced_at type timestamp without time zone
    """, callback

