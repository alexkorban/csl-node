module.exports = (req) ->
    req.db.follower.jsonArrayQuery """
        with relevant_events as (
            select events.type::text, events.geometry_id, events.position, events.properties, events.user_id, events.geometry_name,
                extract(epoch from events.created_at)::int
                    + (case when type = 'entry' then 1 else 0 end) -- make sure entries appear after exits if both have the same time
                as timestamp,
                to_char(events.created_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as created_at,
                users.name as user_name
            from events
            join users on users.id = user_id
            join user_roles on users.role_id = user_roles.id
            where events.project_id = $1
                and (case when $2 = 0 then true else users.id = $2 end)
                and (case when $3 = 0 then true else user_roles.id = $3 end)
                and events.created_at between (($4::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                              (($5::timestamp without time zone) at time zone (select timezone from projects where id = $1)  + '1 day'::interval - '1 second'::interval)
        )
        select * from relevant_events
        union all
        select type::text, null as geometry_id, null as position, null as properties, user_id,
            null as geometry_name,
            extract(epoch from info_events.created_at)::int as timestamp,
            to_char(info_events.created_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as created_at,
            users.name as user_name
        from info_events
        join users on users.id = user_id
        where (type = 'app_start' or type = 'app_stop')
            and user_id in (select distinct user_id from relevant_events)
            and info_events.created_at between (($4::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                               (($5::timestamp without time zone) at time zone (select timezone from projects where id = $1)
                                                    + '1 day'::interval - '1 second'::interval)
        order by user_name, user_id, timestamp
    """
    , req.params.projectId
    , req.query.userId
    , (req.query.roleId ? 0)
    , req.query.dateRange[0], req.query.dateRange[1]
