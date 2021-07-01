dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql "commit", ->
        db.runSql "create type beacon_event_type as enum ('entry', 'exit')", ->
            db.runSql "begin", ->
                db.runSql """
                    create table beacon_roles (
                        id bigserial primary key,
                        name varchar not null,
                        properties json not null default '{}'::json,
                        created_at timestamp without time zone not null default now(),
                        updated_at timestamp without time zone not null default now(),
                        deleted_at timestamp without time zone not null default '-infinity'
                    );
                    create unique index beacon_roles_name on beacon_roles (name);
                    insert into beacon_roles (name) values ('Break area');

                    create table beacons (
                        id bigserial primary key,
                        beacon_uuid uuid not null,
                        major integer not null,
                        minor integer not null,
                        name varchar not null,
                        description text not null default '',
                        customer_id bigint not null,
                        project_id bigint not null,
                        role_id bigint not null,
                        created_at timestamp without time zone not null default now(),
                        updated_at timestamp without time zone not null default now(),
                        deleted_at timestamp without time zone not null default '-infinity',

                        constraint customer_id_ref foreign key (customer_id) references customers,
                        constraint project_id_ref foreign key (project_id) references projects,
                        constraint role_id_ref foreign key (role_id) references beacon_roles
                    );
                    create index beacons_on_role_id on beacons (role_id);
                    create index beacons_on_customer_id on beacons (customer_id);
                    create unique index beacons_on_beacon_uuid_major_minor on beacons (beacon_uuid, major, minor);

                    create table beacon_events (
                        id bigserial primary key,
                        type beacon_event_type,
                        properties json not null default '{}'::json,
                        user_id bigint not null,
                        project_id bigint not null,
                        beacon_id bigint not null,
                        position json,
                        created_at timestamp with time zone not null default now(),
                        updated_at timestamp with time zone not null default now(),
                        recorded_at timestamp with time zone not null default now(),

                        constraint user_id_ref foreign key (user_id) references users,
                        constraint project_id_ref foreign key (project_id) references projects,
                        constraint beacon_id_ref foreign key (beacon_id) references beacons
                    );
                    create index beacon_events_on_user_id on beacon_events (user_id);
                    create index beacon_events_on_project_id on beacon_events (project_id);
                    create index beacon_events_on_beacon_id on beacon_events (beacon_id);
                    create index beacon_events_on_created_at on beacon_events (created_at);
                    create index beacon_events_on_type on beacon_events (type);
                """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists beacon_events;
        drop table if exists beacons;
        drop table if exists beacon_roles;
        drop type if exists beacon_event_type;
    """, callback

