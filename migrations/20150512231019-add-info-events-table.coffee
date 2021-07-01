dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create type info_event_type as enum ('app_start', 'upload');
        create table info_events (
            id bigserial primary key,
            type info_event_type not null,
            user_id bigint not null,
            project_id bigint,
            properties json not null,
            created_at timestamp with time zone not null default now(),
            recorded_at timestamp with time zone not null default now(),
            constraint user_id_ref foreign key (user_id) references users,
            constraint project_id_ref foreign key (project_id) references projects
        );
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists info_events;
        drop type if exists info_event_type;
    """, callback

