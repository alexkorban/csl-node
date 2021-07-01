querystring = require "querystring"

varsSql = """
    with vars as (
        select *, tstamp at time zone timezone as start_time
            , least(clock_timestamp(), tstamp at time zone timezone + '23:59:59'::interval)
                as end_time
        from (
            select $1::bigint as project_id, ($2::timestamp without time zone) as tstamp
                , (select timezone from projects where id = $1) as timezone
        ) a
    )
"""

aggBeaconEventsSql = """
    #{varsSql}
    , trucks as (
        select users.id
        from users
        join user_roles on role_id = user_roles.id
        join users_projects on users_projects.user_id = users.id
            and users_projects.project_id = (select project_id from vars)
        where user_roles.name = 'Concrete truck'
            and synced_at at time zone (select timezone from vars) >=
                date_trunc('day', clock_timestamp() at time zone (select timezone from vars))
    )
    -- This is using the well known "island" technique to mark sequences of adjacent proximity events
    -- for one (user, beacon) so we can later aggregate based on adjacency
    , relevant_beacon_events as (
        select user_id, beacon_id, beacon_events.created_at
            , beacon_roles.name as role_name, beacon_events.name as name
            , type
            , row_number() over (partition by user_id order by beacon_events.created_at, beacon_events.id) -
                row_number() over (partition by user_id, beacon_id
                                   order by beacon_events.created_at, beacon_events.id)
                as island
        from beacon_events
        join beacon_roles on role_id = beacon_roles.id
        where beacon_roles.name in ('Batch plant', 'Paver')
            and user_id in (select id from trucks)
            and beacon_events.project_id = (select project_id from vars)
            and beacon_events.created_at between (select start_time from vars) and (select end_time from vars)
    )
    , agg_beacon_events as (
        select user_id, role_name, beacon_id, name, min(created_at) as entered_at, max(created_at) as left_at
            , last(type order by created_at) as end_type
        from relevant_beacon_events
        group by user_id, role_name, beacon_id, name, island
    )
"""

getTruckInfoFromDockets = (req, res) ->
    req.db.follower.jsonQuery """
        with load_events as (
            select user_id, last(properties order by created_at)->>'docket_id' as docket_id
            from events
            where type = 'concrete_movement' and properties->>'step' = 'load' and project_id = $1
                and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                    (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
            group by user_id
        )
        , dump_events as (
            select properties->>'docket_id' as docket_id, true as dumped
            from events
            where type = 'concrete_movement' and properties->>'step' = 'dump' and project_id = $1
                and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                    (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
        )
        select
            sum(case when truck_wheel_count = 6 and dumped is null then 1 else 0 end) as loaded6wheelers,
            sum(case when truck_wheel_count = 8 and dumped is null then 1 else 0 end) as loaded8wheelers,
            sum(case when truck_wheel_count = 6 and dumped then 1 else 0 end) as empty6wheelers,
            sum(case when truck_wheel_count = 8 and dumped then 1 else 0 end) as empty8wheelers
        from load_events
        join users on load_events.user_id = users.id
        left join dump_events on load_events.docket_id = dump_events.docket_id
    """
    , req.params.projectId, req.query.date


getBatchPlantInfoFromDockets = (req, res) ->
    req.db.follower.jsonArrayQuery """
        with report_events as (
            select *, properties->>'docket_id' as docket_id, properties->>'batch_plant_name' as batch_name
            from events
            where type = 'concrete_movement' and project_id = $1 and properties->>'step' != 'invalid'
                 and created_at between (($2::timestamp without time zone)
                                            at time zone (select timezone from projects where id = $1))
                                        and
                                        (($2::timestamp without time zone)
                                            at time zone (select timezone from projects where id = $1)
                                            + '1 day'::interval - '1 second'::interval)
        )
        , loads as (
            select docket_id as id, created_at, batch_name
                , (properties->'docket_details'->>'load_volume')::double precision as load_volume
                , (properties->'docket_details'->>'delivered_volume')::double precision as delivered_volume
            from report_events
            where properties->>'step' = 'load'
        )
        , tests as (
            select docket_id as id, created_at, batch_name
                , ((properties->'test_details'->>'initial_slump') is not null or
                    (properties->'test_details'->>'final_slump') is not null) as tested_ok
                , (properties->'docket_details'->>'load_volume')::double precision as load_volume
                , (properties->'docket_details'->>'delivered_volume')::double precision as delivered_volume
            from report_events
            where properties->>'step' = 'test'
        )
        , dumps as (
            select docket_id as id, batch_name, created_at
                , (properties->'docket_details'->>'load_volume')::double precision as load_volume
                , (properties->'docket_details'->>'delivered_volume')::double precision as delivered_volume
            from report_events
            where properties->>'step' = 'dump'
        )
        , docket_ids as (
            select id from loads
            union
            select id from tests
            union
            select id from dumps
        )
        , dockets as (
            select coalesce(loads.id, tests.id, dumps.id) as id
                , coalesce(loads.batch_name, tests.batch_name, dumps.batch_name) as batch_name
                , least(loads.created_at, tests.created_at, dumps.created_at) as first_scanned_at
                , coalesce(loads.load_volume, tests.load_volume, dumps.load_volume) as load_volume
                , coalesce(loads.delivered_volume, tests.delivered_volume, dumps.delivered_volume)
                    as delivered_volume
                , dumps.created_at as dump_time
                , case when (dumps.created_at is not null or tested_ok) then 1 else 0 end as load_count
            from docket_ids
            left join loads on loads.id = docket_ids.id
            left join tests on tests.id = docket_ids.id
            left join dumps on dumps.id = docket_ids.id
        )
        , in_transit as (
            select batch_name as name
                , sum(load_volume) as volume_in_transit
            from dockets
            where dump_time is null
            group by batch_name
        )
        , final as (
            select batch_name as name, sum(load_count) as load_count,
                case when clock_timestamp() - min(first_scanned_at) < '15 minutes'::interval then null
                    else
                        round((last(delivered_volume order by first_scanned_at) /
                            (extract(epoch from age(clock_timestamp(), min(first_scanned_at))) / 3600))::numeric, 0)
                    end as volume_per_hour
                , last(delivered_volume order by first_scanned_at) as volume_produced
                , to_char(first(first_scanned_at order by first_scanned_at)
                    at time zone (select timezone from projects where id = $1), 'HH24:MI') as start_time
            from dockets
            group by batch_name
            order by batch_name
        )
        select final.*, coalesce(volume_in_transit, 0) as volume_in_transit
        from final
        left join in_transit using (name)
    """
    , req.params.projectId, req.query.date


getPaverInfoFromDockets = (req, res) ->
    req.db.follower.jsonArrayQuery """
        with daily_events as (
            select *, properties->>'docket_id' as docket_id, properties->'docket_details'->>'project_name' as paver_id
            from events
            where type = 'concrete_movement' and project_id = $1 and properties->>'step' != 'invalid'
                  and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1))
                                 and     (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
        )
        , loads as (select docket_id as id, paver_id, created_at as load_time from daily_events where properties->>'step' = 'load')
        , dumps as (select docket_id as id, paver_id, created_at as dump_time from daily_events where properties->>'step' = 'dump')
        , dockets as (
          select load_time, dump_time,
                 coalesce(loads.id, dumps.id) as id,
                 coalesce(loads.paver_id, dumps.paver_id) as paver_id
          from loads full outer join dumps on loads.id = dumps.id
        )
        , dockets_final as (
          select id, paver_id,
          (case when dump_time > load_time then (dump_time - load_time) else null end) as travel_time,
          (case when dump_time is not null then 1 else 0 end) as load_count
          from dockets
        )
        , events_agg as (
            select paver_id
                   , sum(load_count) as loads
                   , (case when avg(travel_time) is null then '00:00:00' else avg(travel_time) end) as travel_time
            from dockets_final
            group by paver_id
            order by paver_id
        )
        select * from events_agg
    """
    , req.params.projectId, req.query.date


handlers =
    getTruckInfo: (req, res) ->
        if !req.query.debug?.paving? && req.customerId != 3      # Hack for FH trial
            getTruckInfoFromDockets(req, res)
        else
            req.db.follower.jsonQuery """
                with relevant_events as (
                    select beacon_events.type, beacon_events.properties, beacon_events.user_id, beacon_events.project_id,
                           beacon_events.beacon_id, beacon_events.created_at, beacon_roles.name as role
                    from beacon_events
                    join beacon_roles on beacon_events.role_id = beacon_roles.id
                    where (
                        (type = 'exit' and beacon_roles.name = 'Batch plant')
                        or (type = 'entry' and beacon_roles.name = 'Paver')
                    )
                    and beacon_events.project_id = $1
                    and beacon_events.created_at between
                        (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1))
                        and
                        (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)
                            + '1 day'::interval - '1 second'::interval)
                )
                , trucks as (
                    select user_id, last(role order by created_at) = 'Batch plant' as is_loaded
                    from relevant_events
                    group by user_id
                )
                select
                    sum(case when truck_wheel_count = 6 and is_loaded then 1 else 0 end) as loaded6wheelers
                    , sum(case when truck_wheel_count = 8 and is_loaded then 1 else 0 end) as loaded8wheelers
                    , sum(case when truck_wheel_count = 6 and not is_loaded then 1 else 0 end) as empty6wheelers
                    , sum(case when truck_wheel_count = 8 and not is_loaded then 1 else 0 end) as empty8wheelers
                    , true as is_beacon_based
                from trucks
                join users on trucks.user_id = users.id
            """
            , req.params.projectId, req.query.date


    getBatchPlantInfo: (req, res) ->
        if !req.query.debug?.paving? && req.customerId != 3      # Hack for FH trial
            getBatchPlantInfoFromDockets(req, res)
        else
            beaconEventsPromise = req.db.follower.jsonArrayQuery """
                #{aggBeaconEventsSql}
                , linked_beacon_events as (
                    select *
                        , coalesce((role_name = 'Batch plant'
                            and lead(role_name, 1) over (partition by user_id order by entered_at) = 'Paver'
                            and lead(end_type, 1) over (partition by user_id order by entered_at) = 'exit'), false)
                        as is_dumped
                    from agg_beacon_events
                )
                select *, extract(epoch from left_at) as coord, extract(epoch from entered_at) as entered_at_utc
                    , 'load_exit' as type
                from linked_beacon_events
                where role_name = 'Batch plant' and end_type = 'exit'
            """
            , req.params.projectId, req.query.date

            testsPromise = req.db.follower.jsonArrayQuery """
                #{varsSql}
                , tests as (
                    select properties->>'docket_id' as docket_id
                        , created_at as tested_at
                        , extract(epoch from created_at) as coord
                        , ((properties->'test_details'->>'initial_slump') is not null or
                            (properties->'test_details'->>'final_slump') is not null) as tested_ok
                        , (properties->'docket_details'->>'load_volume')::double precision as load_volume
                        , (properties->'docket_details'->>'delivered_volume')::double precision as delivered_volume
                        , to_timestamp((properties->'docket_details'->>'date_time_string'), 'MM/DD/YYYY HH:MI:SS AM')::timestamp
                            -- The above ::timestamp combined with the following line will convert the time string
                            -- from project back to UTC
                            at time zone (select timezone from vars) as loaded_at
                        , 'test' as type
                    from events
                    where type = 'concrete_movement' and properties->>'step' = 'test'
                        and project_id = (select project_id from vars)
                        and created_at between (select start_time from vars) and (select end_time from vars)
                )
                select * from tests
            """
            , req.params.projectId, req.query.date

            Promise.props {beaconEvents: beaconEventsPromise, tests: testsPromise}
            .then (result) ->
                if R.isEmpty result.beaconEvents
                    return []

                adornedBeaconEvents = if !R.isEmpty result.tests  # Match up beacon events to tests and pick out load volume
                    makeLoadTestPairs = R.pipe R.values
                        , R.flatten                         # Combine batch plant records (X) with tests (T)
                        , R.sortBy(R.prop "coord")          # Sort by batch plant exit time and test time
                        , R.groupWith(R.eqProps "type")     # Group adjacent items of the same type
                        , R.aperture(2)                     # Look at pairs of arrays of X or T items
                        , R.filter((pair) -> pair[0][0].type == "load_exit" && pair[1][0].type == "test")
                        , R.chain(R.apply R.zip)            # Convert any X{m}T{n} (m, n > 1) to (XT){min(m, n)}
                        , R.map((pair) -> R.merge pair[0], loadVolume: pair[1].loadVolume) # Adorn X with loadVolume from T

                    makeLoadTestPairs result
                else
                    result.beaconEvents  # no loadVolume when there are no test records

                reduceWith = (func, prop, initialValue, list) ->
                    R.reduce(func(R.prop prop), {"#{prop}": initialValue}, list)[prop]

                volumeProduced = reduceWith(R.maxBy, "deliveredVolume", -1, result.tests)
                volumeInTransit = R.pipe(R.reject(R.prop("isDumped")), R.map(R.prop("loadVolume")), R.sum) adornedBeaconEvents
                startTime = reduceWith(R.minBy, "enteredAtUtc", Infinity, result.beaconEvents)
                endTime = reduceWith(R.maxBy, "coord", 0, result.beaconEvents)
                hoursWorked = (endTime - startTime) / 3600
                volumePerHour = Math.round(volumeProduced / hoursWorked)
                loadCount = result.beaconEvents.length - R.reject(R.prop("testedOk"), result.tests).length

                [{
                    name: result.beaconEvents[0].name
                    startTime: startTime
                    loadCount: loadCount
                    volumeInTransit: volumeInTransit
                    volumePerHour: if volumePerHour < 0 then null else volumePerHour
                    volumeProduced: if volumeProduced < 0 then null else volumeProduced
                    isBeaconBased: true
                }]


    getPaverInfo: (req, res) ->
        if !req.query.debug?.paving? && req.customerId != 3      # Hack for FH trial
            getPaverInfoFromDockets(req, res)
        else
            req.db.follower.jsonArrayQuery """
                #{aggBeaconEventsSql}
                , travel_times as (
                    select *
                        , case when role_name = 'Paver' and lag(role_name, 1)
                                                            over (partition by user_id order by entered_at) = 'Batch plant'
                            then entered_at - lag(left_at, 1) over (partition by user_id order by entered_at)
                            else null end
                            as travel_time
                    from agg_beacon_events
                )
                , final_agg as (
                    select name as paver_id
                       , count(*) as loads
                       , (case when avg(travel_time) is null then '00:00:00' else avg(travel_time) end) as travel_time
                       , true as is_beacon_based
                    from travel_times where role_name = 'Paver'
                    group by name
                    order by name
                )
                select * from final_agg
            """
            , req.params.projectId, req.query.date


    getPaverTravelInfo: (req, res) ->
        req.db.follower.jsonArrayQuery """
            with pavers as
            (
                select users.* from users
                join user_roles on users.role_id = user_roles.id
                where user_roles.name = 'Paver' and project_id = $1
                order by greatest(created_at, updated_at) desc
                limit 1
            )
            , road as (
                -- geog field is constructed here as an optimisation for use in further CTEs
                select geometries.geometry, geometries.geometry::geography as geog,
                coalesce((overlays.properties->>'start_chainage')::float, 0.0) as start_chain,
                case when (overlays.properties->>'start_chainage_point') is null
                     then 0.0
                     else ST_LineLocatePoint(geometries.geometry,
                            ST_SetSRID(
                              ST_Point((overlays.properties->'start_chainage_point'->>'lon')::float,
                                       (overlays.properties->'start_chainage_point'->>'lat')::float), 4326))
                     end
                     as start_chain_on_road
                from overlays
                join geometries on overlays.id = geometries.overlay_id and geometries.deleted_at = '-infinity'
                where overlays.name = 'Centreline' and project_id = $1 and overlays.deleted_at = '-infinity'
                limit 1
            )
            , paver_positions as (
                select positions.*
                from positions join pavers on pavers.id = positions.user_id
                where positions.project_id = $1
                and positions.accuracy < $3
                and positions.created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1))
                                         and     (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) +
                                            '1 day'::interval - '1 second'::interval)
            )
            -- The following start/end CTEs are structured for better performance
            , start_positions as (
                select * from paver_positions order by created_at asc limit $5 * 10
            )
            , end_positions as (
                select * from paver_positions order by created_at desc limit $5 * 10
            )
            , start_positions_near_road as (
                select start_positions.*, road.*, ST_SetSRID(ST_Point(start_positions.lon, start_positions.lat), 4326) as st_pos
                from start_positions, road
                where ST_Distance(road.geog,
                    ST_SetSRID(ST_Point(start_positions.lon, start_positions.lat), 4326)) <= $4
                limit 6
            )
            , end_positions_near_road as (
                select end_positions.*, road.*, ST_SetSRID(ST_Point(end_positions.lon, end_positions.lat), 4326) as st_pos
                from end_positions, road
                where ST_Distance(road.geog,
                    ST_SetSRID(ST_Point(end_positions.lon, end_positions.lat), 4326)) <= $4
                limit 6
            )
            , start_fractions as (
                select ST_LineLocatePoint(geometry, st_pos) as chain, ($3 - accuracy) ^ 2 as weight
                from start_positions_near_road
            )
            , end_fractions as (
                select ST_LineLocatePoint(geometry, st_pos) as chain, ($3 - accuracy) ^ 2 as weight
                from end_positions_near_road
            )
            , averaged as (
                select (select sum(chain * weight) / sum(weight) from start_fractions) as start_p
                    , (select sum(chain * weight) / sum(weight) from end_fractions) as end_p
            )
            , road_lines as (
                select start_chain,
                ST_LineSubstring(road.geometry,
                    least(averaged.start_p, averaged.end_p), greatest(averaged.start_p, averaged.end_p)) as travel,
                ST_LineSubstring(road.geometry,
                    least(averaged.start_p, road.start_chain_on_road), greatest(averaged.start_p, road.start_chain_on_road)) as line_to_start,
                ST_LineSubstring(road.geometry,
                    least(averaged.end_p, road.start_chain_on_road), greatest(averaged.end_p, road.start_chain_on_road)) as line_to_end
                from averaged, road
            )
            , sums as (
                select
                    min_chain_part.total   as min_chainage,
                    start_chain_part.total as start_chainage,
                    end_chain_part.total   as end_chainage,
                    distance_part.total    as distance,
                    end_time_part.end - start_time_part.start as time
                from
                    (select start_chain as total from road) as min_chain_part,
                    (select ST_Length(line_to_start::geography) + start_chain as total from road_lines) as start_chain_part,
                    (select ST_Length(line_to_end::geography) + start_chain as total from road_lines) as end_chain_part,
                    (select ST_Length(travel::geography) as total from road_lines) as distance_part,
                    (select last(created_at order by created_at) as end from end_positions_near_road) as end_time_part,
                    (select first(created_at order by created_at) as start from start_positions_near_road) as start_time_part
            )
            select
                (case when sums.distance is null then 0 else sums.distance end) as total_distance,
                abs(case when sums.distance is null or sums.time is null or sums.time = '0:0:0' then 0
                     else (sums.distance / (extract(epoch from sums.time) / 60.0))
                     end)
                     as avg_speed,
                coalesce(sums.end_chainage, sums.min_chainage) as current_chainage,
                coalesce(sums.start_chainage, sums.min_chainage) as start_chainage
            from sums
        """
        , req.params.projectId, req.query.date, 21, 40.0, 6


    getSlump: (req, res) ->
        req.db.follower.jsonArrayQuery """
            with test_events as (
                select extract('hour' from created_at at time zone (select timezone from projects where id = $1)) as hour, properties
                from events
                where type = 'concrete_movement' and properties->>'step' = 'test' and project_id = $1
                    and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                        (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
                    and properties->>'batch_plant_name' = $3
            )
            , averages as (
                select hour, round(avg((properties->'test_details'->>'initial_slump')::int), 0)::int as slump from test_events
                group by hour
            )
            , hours as ( -- from the hour of the first test today to the current hour
                select generate_series(
                    min(hour)::int
                    extract('hour' from clock_timestamp() at time zone (select timezone from projects where id = $1))::int) as hour
                from test_events
            )
            select hours.hour, coalesce(averages.slump, 0) as slump
            from hours
            left join averages on hours.hour = averages.hour
            order by hour
        """
        , req.params.projectId, req.query.date, req.query.batchPlant


    getProduction: (req, res) ->
        req.db.follower.jsonArrayQuery """
            with filtered_events as
            (
                select
                    properties->>'docket_id' as docket_id,
                    extract('hour' from created_at at time zone (select timezone from projects where id = $1)) as hour,
                    (properties->'docket_details'->>'load_volume')::numeric as volume
                from events
                where type = 'concrete_movement' and project_id = $1
                      and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                             (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
                      and properties->>'batch_plant_name' = $3
                      and (properties->'docket_details'->>'load_volume') is not null
            )
            , by_docket as (
                select min(hour) as hour, first(volume) as volume
                from filtered_events
                group by docket_id
            )
            , volumes as (
                select hour, round(sum(volume), 0)::int as volume
                from by_docket
                group by hour
            )
            , hours as ( -- from the hour of the first test today to the current hour
                select generate_series(
                    min(hour)::int,
                    extract('hour' from clock_timestamp() at time zone (select timezone from projects where id = $1))::int) as hour
                from by_docket
            )
            select hours.hour, coalesce(volumes.volume, 0) as volume
            from hours
            left join volumes on hours.hour = volumes.hour
            order by hour
        """
        , req.params.projectId, req.query.date, querystring.unescape req.query.batchPlant


module.exports = (helpers) ->
    getTruckInfo: helpers.withErrorHandling (req, res) ->
        handlers.getTruckInfo(req, res).then (result) ->
            res.json result


    getBatchPlantInfo: helpers.withErrorHandling (req, res) ->
        handlers.getBatchPlantInfo(req, res).then (result) ->
            res.json result


    getSlump: helpers.withErrorHandling (req, res) ->
        handlers.getSlump(req, res).then (result) ->
            res.json result


    getProduction: helpers.withErrorHandling (req, res) ->
        handlers.getProduction(req, res).then (result) ->
            res.json result


    getPaverInfo: helpers.withErrorHandling (req, res) ->
        Promise.all [handlers.getPaverInfo(req, res), handlers.getPaverTravelInfo(req, res)]
            .then (results) ->
                # Merge together the results of both queries using the paverId
                # (since we have no paver id for now just give each paver the same stats)

                paversList = R.head results
                travelStats = R.head R.last results
                merged = R.map (R.merge travelStats), paversList

                res.json merged
