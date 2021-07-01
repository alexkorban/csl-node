dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create type platform_type as enum ('Android', 'iOS');
        alter table users add platform platform_type;

        -- First get the platform information from the app_start records
        update users set platform = 'Android'
        where (select properties->>'platform' ilike 'Android%'
               from info_events
               where type = 'app_start' and user_id = users.id
               order by created_at desc limit 1);

        update users set platform = 'iOS'
        where (select properties->>'platform' ilike 'iOS%'
               from info_events
               where type = 'app_start' and user_id = users.id
               order by created_at desc limit 1);

        -- Some users may not have an app_start record, so also update the platform using diagnostics records
        update users set platform = 'Android'
        where (select properties->>'os' ilike 'Android%'
               from info_events
               where type = 'diagnostics' and user_id = users.id
               order by created_at desc limit 1);

        update users set platform = 'iOS'
        where (select properties->>'os' ilike 'iOS%'
               from info_events
               where type = 'diagnostics' and user_id = users.id
               order by created_at desc limit 1);

        -- Some users don't have any app_start or diagnostics info_events so we don't know their platform.
        -- All of these are old, inactive users. Set their platform arbitrarily to allow us to mark the platform
        -- column not null.
        update users set platform = 'Android' where platform is null;

        alter table users alter platform set not null;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users drop platform;
        drop type if exists platform_type;
    """, callback

