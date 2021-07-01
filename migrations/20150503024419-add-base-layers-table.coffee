dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table base_layers (
            project_id bigint not null,
            map_id varchar(255) not null,
            max_zoom int not null default 21,
            created_at timestamp with time zone not null default now(),
            deleted_at timestamp with time zone not null default '-infinity',
            constraint project_id_ref foreign key (project_id) references projects
        )
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists base_layers
    """, callback

