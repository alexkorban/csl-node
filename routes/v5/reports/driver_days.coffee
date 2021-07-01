module.exports = (req) ->
    req.db.follower.jsonArrayQuery """
        with vars as (
            select *, start_tstamp at time zone timezone as start_time, $2::bigint as user_id, $3::bigint as role_id
            from (
                select $1::bigint as project_id, ($4::timestamp without time zone) as start_tstamp
                    , ($5::timestamp without time zone) as end_tstamp
                    , (select timezone from projects where id = $1) as timezone
            ) a
        )
        , drivers as (
            select users.id as user_id, users.name as user_name, user_roles.name as role, users.company, users.truck_no
            from users
            join user_roles on users.role_id = user_roles.id
            join users_projects on users.id = user_id and users_projects.project_id = (select project_id from vars)
            where
                -- Only those users who have synced since the start of the requested interval
                (select max(synced_at) from users_projects where user_id = users.id) >= (select start_time from vars)

                -- Only specific user and role (when supplied)
                and (case when (select user_id from vars) = 0 then true else users.id = (select user_id from vars) end)
                and (case when (select role_id from vars) = 0 then true else user_roles.id = (select role_id from vars) end)

                -- Only specific roles
                and (user_roles.properties->>'belongs_to_cor')::bool
        )
        , days as (
            select day, day at time zone (select timezone from vars) at time zone 'UTC' as day_start
                , (day at time zone (select timezone from vars) at time zone 'UTC') + interval '1 day' as day_end
                , user_id, truck_no
            from drivers
            cross join (select generate_series((select start_tstamp from vars),
                                               (select end_tstamp from vars), '1 day') as day) dates
        )
        , activity as (
            select * from days
            join lateral (
                select min(created_at) as first_signon_at
                    , first(properties->>'truck_number' order by created_at) as signon_truck_no
                from signon_events
                where project_id = (select project_id from vars) and user_id = days.user_id
                    and created_at >= day_start and created_at < day_end
            ) q2 on true
            join lateral (
                select last(created_at order by created_at) as latest_move_event_at
                    , last(type order by created_at) as latest_move_event_type
                from events
                where project_id = (select project_id from vars) and user_id = days.user_id and type in ('move', 'stop')
                    and created_at >= day_start and created_at < day_end
            ) q3 on true
        )
        , activity_range as (
            select activity.user_id, activity.day, coalesce(signon_truck_no, truck_no) as truck_no, first_signon_at
                , coalesce(first_signon_at,
                        (select min(created_at) from positions
                            where user_id = activity.user_id and project_id = (select project_id from vars)
                            and created_at >= day_start and created_at < day_end),
                        activity.day::timestamp at time zone (select timezone from vars)) as start
                -- It may happen that the latest events and positions occurred before signon; in that case,
                -- use the signon time as the end time
                , greatest(case when latest_move_event_type is null or latest_move_event_type = 'move' then
                    -- Try to get the latest position time; if no positions available, then use the latest move
                    -- event time; finally, fall back to signon time - no positions & no events means no activity.
                    coalesce((select max(created_at)
                             from positions
                             where user_id = activity.user_id and project_id = (select project_id from vars)
                                   and created_at >= day_start and created_at < day_end
                             )
                        , latest_move_event_at, first_signon_at
                        , activity.day::timestamp at time zone (select timezone from vars))
                    else latest_move_event_at
                    end
                  , first_signon_at
                  , activity.day::timestamp at time zone (select timezone from vars)) as end
            from activity
        )
        , combined as (
            select to_char(activity_range.day, 'DD/MM/YY HH24:MI:SS') as day
                , extract(epoch from activity_range.day at time zone (select timezone from vars)
                    at time zone 'UTC')::int as day_start_utc
                , extract(epoch from activity_range.day at time zone (select timezone from vars)
                    at time zone 'UTC' + interval '1 day' - interval '1 second')::int as day_end_utc
                , drivers.user_id, drivers.user_name, drivers.role, drivers.company, activity_range.truck_no
                , to_char(activity_range.start at time zone (select timezone from vars),
                    'DD/MM/YY HH24:MI:SS') as start
                , to_char(activity_range.end at time zone (select timezone from vars),
                    'DD/MM/YY HH24:MI:SS') as end
                , activity_range.end - activity_range.start as total_active_time
                , extract(epoch from activity_range.first_signon_at)::int as signon_at_utc
                , (select timezone from vars) as timezone
            from drivers
            join activity_range on drivers.user_id = activity_range.user_id
            order by activity_range.day, drivers.user_name
        )
        select * from combined
    """
    , req.params.projectId, req.query.userId, req.query.roleId, req.query.dateRange[0], req.query.dateRange[1]
