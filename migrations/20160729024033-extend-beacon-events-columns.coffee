dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table beacon_events add column role_id bigint default null,
                                  add column name varchar default null,
                                  add column description text default null;

        create index beacon_events_on_role_id on beacon_events (role_id);
        create index beacon_events_on_name    on beacon_events (name);

        -- assign the correct beacon details to existing events
        update beacon_events set role_id = beacons.role_id, name = beacons.name, description = beacons.description
            from beacons where beacons.id = beacon_id;

        -- no longer allow nulls
        alter table beacon_events alter column role_id drop default;
        alter table beacon_events alter column name drop default;

        -- Now that all events have valid roles we can add the FK constraint
        alter table beacon_events
            add constraint role_id_ref foreign key (role_id) references beacon_roles(id);
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table beacon_events drop if exists role_id;
        alter table beacon_events drop if exists name;
        alter table beacon_events drop if exists description;
    """, callback

