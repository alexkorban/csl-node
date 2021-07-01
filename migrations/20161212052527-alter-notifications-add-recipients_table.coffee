dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        drop table if exists notifications;
        create type notification_type as enum ('entry', 'exit');
        create table notifications (
            id bigserial primary key,
            project_id bigint not null references projects,
            geometry_id bigint not null references geometries,
            type notification_type not null,
            role_id bigint references roles,
            user_ids bigint[] not null,
            recipient_ids bigint[] not null,
            is_active boolean not null default false,
            created_at timestamp with time zone not null default now(),
            updated_at timestamp with time zone not null default now(),
            deleted_at timestamp with time zone not null default '-infinity'
        );
        create table notifications_recipients (
            id bigserial primary key,
            project_id bigint not null,
            email varchar not null,
            unique (project_id, email)
        );
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists notifications;
        drop type if exists notification_type;
        drop table if exists notifications_recipients
    """, callback

