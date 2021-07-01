dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table signon_events (
            id bigserial primary key,
            properties json not null default '{}'::json,
            user_id bigint not null,
            project_id bigint not null,
            vehicle_id bigint,
            position json,
            created_at timestamp with time zone not null default now(),
            updated_at timestamp with time zone not null default now(),
            recorded_at timestamp with time zone not null default now(),

            constraint user_id_ref foreign key (user_id) references users,
            constraint project_id_ref foreign key (project_id) references projects,
            constraint vehicle_id_ref foreign key (vehicle_id) references vehicles
        );
        create index signon_events_on_user_id on signon_events (user_id);
        create index signon_events_on_project_id on signon_events (project_id);
        create index signon_events_on_vehicle_id on signon_events (vehicle_id);
        create index signon_events_on_created_at on signon_events (created_at);

        insert into signon_events (properties, user_id, project_id, vehicle_id, position, created_at, updated_at,
            recorded_at)
        select properties, user_id, project_id, null, position, created_at, updated_at, recorded_at
        from events
        where type = 'signon';

        create table vehicle_roles (
            id bigserial primary key,
            name varchar not null,
            properties json not null default '{}'::json,
            created_at timestamp without time zone not null default now(),
            updated_at timestamp without time zone not null default now(),
            deleted_at timestamp without time zone not null default '-infinity'
        );
        create unique index vehicle_roles_name on vehicle_roles (name);
        insert into vehicle_roles (name) values ('Light vehicle'), ('Pool vehicle'), ('Tool of trade');

        alter table vehicles add role_id bigint references vehicle_roles;
        update vehicles set role_id = (select id from vehicle_roles where name = 'Light vehicle');
        alter table vehicles alter role_id set not null;

        alter table roles rename to user_roles;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists signon_events;

        alter table vehicles drop role_id;
        drop table if exists vehicle_roles;

        alter table user_roles rename to roles;
    """, callback

