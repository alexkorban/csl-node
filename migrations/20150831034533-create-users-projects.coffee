dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table users_projects (
            user_id bigint not null references users(id),
            project_id bigint not null references projects(id),
            synced_at timestamp not null default '-infinity'
        );

        insert into users_projects (user_id, project_id, synced_at)
            select user_id, project_id,
                last(created_at order by created_at)
            from positions
            group by user_id, project_id;

        alter table users drop synced_at;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists users_projects;
        alter table users add synced_at timestamp not null default '-infinity';
    """, callback

