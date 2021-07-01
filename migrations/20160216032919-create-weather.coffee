dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table weather (
            id bigserial primary key,
            name varchar not null,
            created_at timestamp without time zone not null,
            lon decimal(9,6) not null,
            lat decimal(9,6) not null,
            air_temp double precision not null,
            pressure double precision not null,
            cloud varchar not null,
            visibility double precision not null,
            press_tend varchar not null,
            rain_trace double precision not null,
            gust_speed double precision not null,
            humidity double precision,
            wind_dir varchar not null,
            wind_speed double precision not null
        );
        create unique index uq_weather_created_at_lon_lat
        on weather (created_at, lon, lat);
        create index weather_created_at
        on weather (created_at);
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop index if exists weather_created_at;
        drop index if exists uq_weather_created_at_lon_lat;
        drop table if exists weather;
    """, callback


