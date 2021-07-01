module.exports = (req) ->
    # Group positions into speed bands together with min and max recorded speed.
    # calculate durations for entry events and group - same as the areas report.
    # then join durations with banded positions based on positions falling into intervals.
    # calculate the percentage spent in each speed band for each interval (i.e. group again with some windowing functions on top).
    # this assumes that the first position in the interval is sufficiently close to the start of the interval
    # (it should be within ~1 minute I think).
    req.db.follower.jsonArrayQuery """
        with vars as (
            select *, start_tstamp at time zone timezone as start_time
                , least(clock_timestamp(),
                    (end_tstamp + '23:59:59'::interval) at time zone timezone) as end_time
                , $4::bigint as user_id, $5::bigint as geometry_id, $6::bigint as role_id
            from (
                select $1::bigint as project_id, ($2::timestamp without time zone) as start_tstamp
                    , ($3::timestamp without time zone) as end_tstamp
                    , (select timezone from projects where id = $1) as timezone
            ) a
        )
        , last_user_sync as (
            select user_id, max(synced_at) as synced_at
            from users_projects
            where case when 0 = 0 then true else user_id = 0 end
            group by user_id
        )
        , relevant_events as (
            select row_number() over
               (partition by user_id, date_trunc('day', events.created_at at time zone (select timezone from vars))
                    , geometry_id order by events.created_at) as row_num
                , user_id, events.project_id, geometry_id, geometry_name, type
                , date_trunc('day', events.created_at at time zone (select timezone from vars)) as day
                , events.created_at
                , lead(events.created_at, 1)
                    over (partition by user_id,
                        date_trunc('day', events.created_at at time zone (select timezone from vars)), geometry_id
                        order by events.created_at rows between current row and 1 following) as pair_time
            from events
            join users on events.user_id = users.id
            join user_roles on user_roles.id = users.role_id
            where events.project_id = (select project_id from vars)
                and (type = 'entry' or type = 'exit')
                and (case when (select user_id from vars) = 0 then true else user_id = (select user_id from vars) end)
                and (case when (select geometry_id from vars) = 0 then true else geometry_id = (select geometry_id from vars) end)
                and (case when (select role_id from vars) = 0 then true else user_roles.id = (select role_id from vars) end)
                and events.created_at between (select start_time from vars) and
                                              (select end_time from vars)
        )
        , visit_intervals as (
            select relevant_events.user_id, relevant_events.day, geometry_id, geometry_name
                , case when type = 'exit' then relevant_events.day at time zone (select timezone from vars) at time zone 'UTC'
                else relevant_events.created_at end as start

                , case when type = 'exit' then relevant_events.created_at
                else coalesce(pair_time,
                              least(synced_at,
                                    relevant_events.day at time zone (select timezone from vars) at time zone 'UTC' + '1 day'::interval - '1 second'::interval))
                end as finish
            from relevant_events
            join last_user_sync on relevant_events.user_id = last_user_sync.user_id
            where type = 'entry' or (type = 'exit' and row_num = 1)
        )
        , intervals_with_pos as (
            select *
            from visit_intervals vi
            join lateral (
                select (case when speed <= 0.1 then 0
                             when speed <= 1.39 then 1
                             when speed <= 4.17 then 2
                             when speed <= 11.11 then 3
                             else 4 end) as speed_band
                    , lead(p.created_at, 1, vi.finish) over (order by p.created_at rows between current row and 1 following)
                        - p.created_at as duration
                    , ST_Distance(
                        ST_SetSRID(ST_Point(lon, lat), 4326)::geography
                        , ST_SetSRID(ST_Point(
                            (lead(lon, 1) over (order by p.created_at rows between current row and 1 following)),
                            (lead(lat, 1) over (order by p.created_at rows between current row and 1 following))
                            ), 4326)) as distance
                    , p.created_at
                    , speed
                from positions p
                where p.created_at >= vi.start and p.created_at < vi.finish
                    and p.user_id = vi.user_id
            ) p1 on true
        )
        , speed_band_intervals as (
            select vis.user_id, geometry_id, day
                , sum(duration) as speed_band_time
                , sum(distance) as speed_band_distance
                , min(speed) as min_speed, max(speed) as max_speed, speed_band
                , first(geometry_name) as geometry_name
            from intervals_with_pos vis
            group by vis.user_id, day, geometry_id, speed_band
        )
        select user_id, geometry_id, speed_band_time, speed_band_distance, min_speed, max_speed
            , speed_band, geometry_name
            , to_char(day, 'DD/MM/YY HH24:MI:SS') as day
            , extract(epoch from speed_band_time) as duration
            , 100 * (extract(epoch from speed_band_time) / extract(epoch from sum(speed_band_time)
                over (partition by user_id, geometry_id, day))) as percentage
            , users.name as user_name, company as user_company
            , coalesce(nullif(user_roles.name, ''), users.description) as user_role
        from speed_band_intervals
        join users on users.id = user_id
        join user_roles on users.role_id = user_roles.id
        order by user_name, day, lower(geometry_name), speed_band
    """
    , req.params.projectId
    , req.query.dateRange[0], req.query.dateRange[1]
    , req.query.userId, req.query.geometryId, (req.query.roleId ? 0)
