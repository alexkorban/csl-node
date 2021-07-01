dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create type permission_type as enum ('view_overlays', 'view_drone_imagery', 'use_demo_mode', 'use_diagnostics');
        create table permissions (
            user_id bigint not null,
            project_id bigint not null,
            permission permission_type not null,
            created_at timestamp with time zone not null default now(),
            deleted_at timestamp with time zone not null default '-infinity',
            constraint user_id_ref foreign key (user_id) references users,
            constraint project_id_ref foreign key (project_id) references projects
        );

        create table project_creds (
            project_id bigint not null,
            permission permission_type not null,
            cred_hash varchar(255) not null,
            unique (project_id, permission),
            constraint project_id_ref foreign key (project_id) references projects
        );
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists permissions;
        drop table if exists project_creds;
        drop type if exists permission_type;
    """, callback

