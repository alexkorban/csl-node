Setup on Heroku
---------------------------------------------

Setup Postgres extension:
  run heroku pg:psql and "create extension postgis;" in there

Clone the local database with:
  PGUSER=alex PGPASSWORD=alex heroku pg:push safetyfirst_development HEROKU_POSTGRESQL_TEAL --app safetyfirstnode-staging

Set search path in heroku pg:psql:
  - Run `heroku pg:credentials DATABASE_URL -a csl-safesitenode` to get the name of the database
  - Run this in psql:
    alter database <DB name, e.g. df9bvjqtn3i2oh> set search_path = '$user', 'public', 'postgis';

  - Restart the psql session, and the search path can be checked with:
    show search_path;

Setup DATABASE_URL env variable for Heroku app, this is required for node-db-migrate to connect to the database:
  heroku config:set DATABASE_URL=`heroku config:get HEROKU_POSTGRESQL_TEAL_URL`

Migrations can be run pretty much normally:
  heroku run node db-migrate -e prod -v up


Fork the database
------------------------------------------------------------------------------------------------------------------------

After forking an application/database, it's necessary to update the search path (see setup instructions).


Restore locally from a database dump
------------------------------------------------------------------------------------------------------------------------

createdb safesite_dev

psql -d safesite_dev  # open the DB in psql

In psql:
create schema postgis;
alter database safesite_dev set search_path = '$user', 'postgis', 'public';
\q

Back on the command line:

cd /usr/local/Cellar/postgis/2.1.4_1/share/postgis

psql -d safesite_dev -f postgis.sql
psql -d safesite_dev -f postgis_comments.sql
psql -d safesite_dev -f spatial_ref_sys.sql

In psql:

alter database safesite_dev set search_path = '$user', 'public', 'postgis';

cd <dump location>
pg_restore --verbose --no-acl --no-owner -d safesite_dev 2015-08-30.dump


Create a project
------------------------------------------------------------------------------------------------------------------------

$ tools/create_project staging "Blake''s Crossing" 1 Australia/Adelaide polygon ../kml/Blake\'s\ crossing/boundary.json


Debug SQL queries
------------------------------------------------------------------------------------------------------------------------

When a query has CTEs (intermediate sub-selects before the main select) or can be refactored into such form, then
it's possible to see the output of intermediate steps:

- Create the debug table:
    create table debug_table (id serial, t text, r text);

- Add a new CTE statement into the query such as:

    debug_a as (insert into debug_table(t,r) select 'vis_int', row(visit_intervals.*)::text from visit_intervals),

  This will dump all the data from the specified sub-table into debug_table.

Note that modifying CTEs (like the debug one) have to be at the top level, which means this only works with the
`query` method of the DB client (not with `jsonQuery` or `jsonArrayQuery`).


Importing LendLease KMLs into the DB as GeoJSON features
------------------------------------------------------------------------------------------------------------------------

Run these commands:

iconv -f UTF-16 -t UTF-8 source_cutfill.kml > cutfill.kml
togeojson cutfill.kml > cutfill.json

Then in psql:

    \set content `cat cutfill.json`
    select j->>'type' as type, j->'properties'->>'Name' as name, j->'geometry' as g
        from (select json_array_elements(:'content'::json->'features') as j) as sub;

    insert into geometries(overlay_id, properties, geometry)
        select ?? as overlay_id, ('{"name":"' || (j->'properties'->>'name') || '"}')::json as properties,
            ST_SetSRID(ST_MakePolygon(ST_Force2D(ST_GeomFromGeoJSON(j->>'geometry'))), 4326) as geometry
        from (select json_array_elements(:'content'::json->'features') as j) as sub
            where j->'properties'->>'name' ilike '%cut%';


Downloading LendLease drone imagery
------------------------------------------------------------------------------------------------------------------------

Download with 10 parallel connections and resume:

aria2c --file-allocation=none -c -x 10 -s 10 -d . <url>
caffeinate -w <aria pid>


Visualising positions from Heroku
------------------------------------------------------------------------------------------------------------------------

psql <conn string from heroku pg:credentials DATABASE_URL> -t -c
    "select st_astext(st_point(lon, lat)) from positions where user_id = 361 and created_at > '2013-05-12 20:00:00' order by created_at desc" | geojsonify | geojsonio


Simplify KML geometries
------------------------------------------------------------------------------------------------------------------------

ogr2ogr -simplify 0.000001 -f KML simplified.kml original.kml


Useful SQL queries
------------------------------------------------------------------------------------------------------------------------

== Set download boundaries
------------------------------------------------------------

update projects set download_boundary = (select st_simplify(st_buffer(geometry::geography, 1000)::geometry, 0.005)
    from geometries join overlays on overlay_id = overlays.id
    where (overlays.properties->>'is_boundary')::bool and project_id = projects.id)
    , updated_at = clock_timestamp() + '1 minute'::interval
    where id = 29;

== Extract positions as (almost correct) GeoJSON:
------------------------------------------------------------

- Execute this in RubyMine:

with features as
    (with coords as (select id, 'Point' as type, ARRAY[lon, lat] as coordinates from positions where user_id = 74),
          props as (select id, accuracy, speed, created_at, recorded_at from positions where user_id = 74)
    select 'Feature' as type, row_to_json(coords.*) as geometry, row_to_json(props.*) as properties
    from coords
      join props on coords.id = props.id)
select '"FeatureCollection"' as type, json_agg(row_to_json(features.*)) as features from features

- Copy to clipboard using the JSON extractor
- the data will be correct but wrongly wrapped in square brackets


== Create a project manually using a JSON boundary in a file:
------------------------------------------------------------

-- boundary.json contains a FeatureCollection (e.g. as output by togeojson when converting from KML)

\set bound `cat ../kml/Dunedin/boundary.json`
begin;

with var as (select 'Dunedin' as project_name, 'TT5AA5' as project_cid, 99 as tpl_boundary_id,
    ST_SetSRID(ST_MakePolygon(ST_Force2D(ST_GeomFromGeoJSON(:'bound'::json#>>'{features,0,geometry}'))), 4326) as geometry
)
, project as (
    insert into projects (name, cid, download_boundary)
        select var.project_name, var.project_cid,
            -- set download boundary to be ~1km away from the project boundary
            st_simplify(st_buffer(var.geometry::geography, 1000)::geometry, 0.005)
        from var
    returning id, download_boundary
)
, boundary as (
    insert into overlays (name, project_id, display_order, properties)
        select 'Boundary', project.id, 100,
            (select properties from overlays where id = var.tpl_boundary_id)
        from var cross join project
    returning id
)
, geom as (
    insert into geometries (overlay_id, properties, geometry)
        select boundary.id, '{"name": "Project boundary"}'::json, var.geometry
        from boundary cross join var
)
select * from geom;


== Insert a geometry using a KML fragment:
------------------------------------------------------------

    begin; insert into geometries (overlay_id, properties, geometry) values (98,
        '{"name": "Clearing line"}'::json, ST_SetSRID(ST_Force2D(ST_GeomFromKML('<Polygon><outerBoundaryIs><LinearRing><coordinates>151.2010508495358,-33.89454214039346,0 151.2010244030993,-33.89550086321904,0 151.2019655764939,-33.89559574476716,0 151.2029649224187,-33.89571585462653,0 151.2033830872738,-33.89562535128356,0 151.2035801360156,-33.89469774959951,0 151.2026081804326,-33.8947415646257,0 151.2026543751532,-33.89431695006977,0 151.2018223789218,-33.89423260397754,0 151.2013299266485,-33.89431101594254,0 151.2010508495358,-33.89454214039346,0</coordinates></LinearRing></outerBoundaryIs></Polygon>')), 4326));

== Insert a marker:
------------------------------------------------------------

    insert into geometries (geometry, properties, overlay_id)
        values (ST_SetSRID(ST_GeomFromGeoJSON('{"type":"Point","coordinates":[174.859505,-41.129325153]}'), 4326), to_json('{"name": "JHA Station 1", "icon": "info"}'), 3);

== Get restricted_areas entries in a readable form:
------------------------------------------------------------

    select properties, ST_AsGeoJSON(geometry) from geometries where overlay_id = 3;


== Format UTC time for the client:
------------------------------------------------------------

    to_char(site_overlay_files.updated_at, 'YYYY-MM-DD HH24:MI:SSZ') as updated_at


== Get a convex hull:
------------------------------------------------------------

    insert into geometries (overlay_id, properties, geometry)
        values (57, '{}'::json,
        (select ST_Buffer(ST_ConcaveHull(geometry, 0.99), 0.001) from geometries where overlay_id = 7));


== Check for duplicate event records
------------------------------------------------------------

with pairs as (
    select id, user_id, geometry_id, created_at, type,
        lead(type, 1) over (partition by user_id, project_id, date_trunc('day', created_at at time zone 'Australia/NSW'), geometry_id
                            order by created_at rows between current row and 1 following) as pair_type
    from events
    order by user_id
 )
 select id, user_id, geometry_id, created_at from pairs where type = pair_type order by user_id;


== Get project activity stats
------------------------------------------------------------

select name, count(distinct user_id) as users, count(events)/2 as area_visits,
    last(events.created_at order by events.created_at) at time zone 'Australia/NSW' as latest_activity
from events join projects on project_id = projects.id group by name;


== Check for event positions outside download boundaries
------------------------------------------------------------

select * from events where position is not null and
    (select count(*) from projects
    where ST_Contains(download_boundary, ST_SetSRID(ST_Point((events.position->>'lon')::double precision,
                                                             (events.position->>'lat')::double precision), 4326))) = 0
order by user_id, created_at;


== Get platform & device information
------------------------------------------------------------

select user_id, last(properties->>'platform' order by created_at) as platform, last(properties->>'device' order by created_at) as device,
    last(properties->>'api_version' order by created_at) as api
    from info_events where type = 'app_start' group by user_id order by platform, device;

== Get paving scan summary
------------------------------------------------------------

select properties->>'docket_id', string_agg(properties->>'step', ',' order by created_at)
from events
where type = 'concrete_movement' and project_id = 17 and created_at > now() - '5 hours'::interval
group by properties->>'docket_id' order by properties->>'docket_id' desc;


== Export query results to CSV
------------------------------------------------------------

\copy (select * from positions where user_id = 974 order by created_at) to '974.csv' with csv header


== Set a JSON property
------------------------------------------------------------

update users_hq set permissions = json_object_set_key(permissions, 'drawing', true) where id = 1;


== Detect possible stuck positions
------------------------------------------------------------

This is a query for Android users, and count > 100 filter assumes high frequency positions:

with u as (select distinct user_id as id from info_events
            where user_id in (select distinct user_id from events where project_id = 17)
                and type = 'app_start' and created_at > now() - interval '60 days'
                and properties->>'platform' ilike 'android%')
select count(*) as cnt, user_id, date_trunc('hour', created_at) as hour, lon, lat, accuracy
    , altitude, altitude_accuracy, speed, heading
from positions
where user_id in (select id from u) and created_at > now() - interval '60 days'
group by user_id, hour, lon, lat, accuracy, altitude, altitude_accuracy, speed, heading
having count(*) > 100
order by hour desc;

False positives are possible so it's still necessary to inspect the positions manually.


== Get user stats for the last 30 days
------------------------------------------------------------

with last_synced_at as (
    select user_id, max(synced_at) as at from users_projects group by user_id
)
, records as (
    select user_id, last(properties->>'platform' order by created_at) as platform, last(properties->>'device' order by created_at) as device,
    last(properties->>'api_version' order by created_at) as api
    from info_events
    where type = 'app_start' group by user_id
)
, grouped_records as (
    select records.user_id, platform, device, api, at
    from records
    left join last_synced_at on records.user_id = last_synced_at.user_id
    where at >= now() - '30 days'::interval
)
select 'Active mobile users today' as name, count(*)::text as value
    from grouped_records
    where at at time zone 'Australia/NSW' >= date_trunc('day', now() at time zone 'Australia/NSW')

union
select 'Active mobile users (30 days)', count(*)::text from grouped_records

union
select 'API versions in use', string_agg(api::text, ', ' order by api) from (select distinct api from grouped_records) a

union
select 'iOS versions', string_agg(platform, ', ' order by platform) from (select distinct platform from grouped_records where platform ilike 'ios%') b

union
select 'Android versions', string_agg(platform, ', ' order by platform) from (select distinct platform from grouped_records where platform ilike 'android%') c

union
select 'Mobile errors today', count(*)::text from info_events where type = 'error' and date_trunc('day', now() at time zone 'Australia/NSW') = date_trunc('day', created_at at time zone 'Australia/NSW')

union
-- Times have to be "at time zone 'Australia/NSW'" once sessions table is fixed
select 'Active HQ users today', count(*)::text from sessions where date_trunc('day', now()) = date_trunc('day', updated_at)

union
-- Times have to be "at time zone 'Australia/NSW'" once sessions table is fixed
select 'Active HQ users (30 days)', count(distinct data->>'userId')::text from sessions where updated_at >= now() - '30 days'::interval

order by name


== Get speed stats
------------------------------------------------------------

with t1 as (select created_at at time zone 'NZ' as local,
    ST_Distance(ST_SetSRID(ST_Point(lon, lat), 4326)::geography,
        ST_SetSRID(ST_Point(lag(lon) over(order by created_at), lag(lat) over(order by created_at)), 4326)::geography) as dist,

    ST_Distance(ST_SetSRID(ST_Point(lon, lat), 4326)::geography,
        ST_SetSRID(ST_Point(first(lon) over(partition by extract(day from created_at at time zone 'NZ') order by created_at), first(lat) over(partition by extract(day from created_at at time zone 'NZ') order by created_at)), 4326)::geography) as dist2,

        speed, accel, heading, lon, lat, accuracy, created_at
from positions
where user_id = 995 and extract(hour from created_at at time zone 'NZ') between 5 and 8 and created_at > now() - interval '7 hours'
)
select local, dist, dist2, speed, accel, extract(epoch from created_at - lag(created_at) over (partition by extract(day from created_at at time zone 'NZ') order by created_at)) as tm, dist / extract(epoch from created_at - lag(created_at) over (partition by extract(day from created_at at time zone 'NZ') order by created_at)) as calc_speed, heading, lon, lat, accuracy, dist - accuracy as diff
from t1
order by created_at desc


== Get acceleration stats
------------------------------------------------------------

with accel as (select abs((accel->>'x')::double precision) as x, abs((accel->>'y')::double precision) as y, abs((accel->>'z')::double precision) as z, speed,
    lag(speed, 1) over (order by created_at) as prev_speed1,
    lag(speed, 2) over (order by created_at) as prev_speed2,
    lag(speed, 3) over (order by created_at) as prev_speed3,
    lead(speed, 1) over (order by created_at) as next_speed1,
    lead(speed, 1) over (order by created_at) as next_speed2,
    created_at
from positions where user_id = 1002 and created_at > '2016-05-26 20:03:00' and created_at < '2016-05-27 03:26:05')

, accel2 as (
select *, sqrt(x*x+y*y+z*z) as mag, greatest(x, y, z) as axmax
from accel
--where speed < 0.01 --and prev_speed = 0 and next_speed > 0
)
, accel3 as (
select *, ntile(10) over (order by mag) as ptile, (mag + lag(mag, 1) over (order by created_at) + lag(mag, 2) over (order by created_at)) / 3 as avg_mag, greatest(axmax + lag(axmax, 1) over (order by created_at) + lag(axmax, 2) over (order by created_at)) as axmax_3
from accel2
)
, accel4 as (
select *, ntile(10) over (order by axmax_3) as ptile2 from accel3
where

-- Stop error
--speed > 0.2 and ((next_speed2 < 0.01 and next_speed1 > 0.01 and  prev_speed1 < 0.01) or (next_speed1 < 0.01 and prev_speed1 > 0.01 and prev_speed2 < 0.01))

-- Move start
speed > 0.01 and prev_speed1 > 0.01 and prev_speed2 > 0.01 and prev_speed3 < 0.01
)
-- select min(mag), max(mag), avg(mag), min(ptile), max(ptile)
-- from accel4

-- select * from accel4

select ptile2, min(axmax_3), max(axmax_3), avg(axmax_3) from accel4 group by ptile2 order by ptile2


API v4 time sending format
server: `extract(epoch from <timestamp column>)::int as time` --> number of seconds
client: `moment.tz(time * 1000, timeZone)` --> moment at project's time zone

API v4 timestamps scheme
------------------------------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------------
File     |    Function/param                | P/C |   Producer/Consumer       | Zone    |  Format
---------|----------------------------------|-----|---------------------------|---------|----------
weather  | created_at                       | <-- |  Meteo data               | UTC     | timestamp
         | created_at                       | --> |  node user.getWeather     |         |
---------|----------------------------------|-----|---------------------------|---------|----------
user     | recordInfoEvent,                 | <-- | mobile.Uplink             | mobile  | moment json
         | recordPosition,                  |     |                           |         |
         | recordEvent,                     |     |                           |         |
         | recordObservation,               |     |                           |         |
         | recordVehicle, created_at        |     |                           |         |
         | recordVehicle, rego_Exp_date     | <-- | mobile, prestartChecklist | mobile  | moment
         | getUpdatedPosition               | --> | mobile                    | project | 'DD/MM/YY HH24:MI:SS'
         | getWeather                       | --> | mobile, weather icon      | UTC     | timestamp
         | getUpdatedCollections,           |     |                           |         |
         | created_at                       | --> | mobile, collections       | project |  'DD/MM/YY HH24:MI:SS'
         | getUpdatedVehicle, rego_exp_date | --> | mobile, vehiclesCollection| mobile  | timestamp
---------|----------------------------------|-----|---------------------------|---------|-----------
reports  | getProjectVisits     timestamp   | --> |                           |         | seconds
         |                      date        | --> |                           |         | 'DD/MM/YY HH24:MI:SS'
         |                      arrived_at  | --> |                           |         | 'HH24:MI'
         |                      departed_at | --> |                           |         | 'HH24:MI'
         | getArea              date        | --> |                           | none    | 'DD/MM/YY HH24:MI:SS'
         |                      duration    | --> |                           | project | seconds
         | getSpeedBands        duration    | --> |                           | project | seconds
         | getTimeline          timestamp   | --> |                           |         | seconds
         |                      created_at  | --> |                           |         | 'DD/MM/YY HH24:MI:SS'
         | getConcreteTests    as_load_time | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         |                     as_test_time | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         |                     as_dump_time | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         | getBreaks          day           | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         |                    day_start_utc | --> | reports, getBreaks        | utc     | seconds
         |                    day_end_utc   | --> | reports, getBreaks        | utc     | seconds
         |                    start         | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         |                    end           | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         |                    coord         | --> |                           |         | msc
---------|----------------------------------|-----|---------------------------|---------|------------
project  | getBaseLayers      updated_at    | --> | BaseLayer.addDroneImage   | project | 'DD/MM/YY HH24:MI:SS'
         | getUsers         last_position_at| --> | UserWatcher               | project | 'DD/MM/YY HH24:MI:SS'
         | getPositions     last_position_at| --> | UserWatcher               | project | 'DD/MM/YY HH24:MI:SS'
         |                  created_at      | --> |                           | project | 'DD/MM/YY HH24:MI:SS'
         | getPositionTimeline   timestamp  | --> |                           |         | msc
         |                  next_timestamp  | --> |                           |         | msc
         | getTimelineInfo           start  | --> |                           |         | msc
         |                          finish  | --> |                           |         | msc
---------|----------------------------------|-----|---------------------------|---------|------------
paving   | getBatchPlantInfo                | --> |                           | project | 'HH24:MI'
         | getSlump                 hour    | --> |                           | project | "hour"
         | getProduction            hour    | --> |                           | project | "hour"
         |


