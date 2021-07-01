module.exports =  (req) ->
    # Select first boundary entry event on each day for each user
    req.db.follower.jsonArrayQuery """
        with boundary as (
            select id
            from geometries
            where overlay_id = (select id from overlays where project_id = $1 and (properties->>'is_boundary')::bool)
            limit 1
        )
        , relevant_events as (
            select type, user_id, events.created_at as created_at,
                date_trunc('day', events.created_at at time zone (select timezone from projects where id = $1)) as day,
                position,
                lead(events.created_at, 1)
                    over (partition by user_id, date_trunc('day', events.created_at at time zone (select timezone from projects where id = $1)), geometry_id
                          order by events.created_at rows between current row and 1 following) as next_time,

                lag(events.created_at, 1)
                    over (partition by user_id, date_trunc('day', events.created_at at time zone (select timezone from projects where id = $1)), geometry_id
                          order by events.created_at rows between 1 preceding and current row) as prev_time,

                lag(position, 1)
                    over (partition by user_id, date_trunc('day', events.created_at at time zone (select timezone from projects where id = $1)), geometry_id
                          order by events.created_at rows between 1 preceding and current row) as prev_pos

            from events
            join users on events.user_id = users.id
            join user_roles on users.role_id = user_roles.id
            where (type = 'entry' or type = 'exit')
                and geometry_id = (select id from boundary)
                and (case when $4 = 0 then true else user_id  = $4 end)
                and (case when $5 = 0 then true else user_roles.id = $5 end)
                and events.created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                              (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
        )
	   , relevant_users as (
			select users.id as user_id, user_roles.name as user_role, user_roles.id as role_id, users.name as user_name
				, users.company as user_company, users.description 
				, (select max(synced_at) from users_projects
					where users_projects.user_id = users.id) as last_synced_at
			from users
			join user_roles on users.role_id = user_roles.id
			join users_projects on users.id = user_id and users_projects.project_id = $1
			where (case when $4 = 0 then true else users.id = $4 end)
				and (case when $5 = 0 then true else user_roles.id = $5 end)
	    )		
        , date_range as (  -- every date in the selected range for every selected user
			select day, user_id
			from relevant_users
              cross join (select generate_series(($2::timestamp without time zone),
                                                 ($3::timestamp without time zone), '1 day') as day) dates
        )
        , position_counts as (
			select date_range.day,
				date_range.user_id,
				(exists (select 1 from positions 
						 where positions.project_id = $1 
						 and positions.user_id = date_range.user_id
						 and positions.created_at 
							between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) 
							and (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
						)
				) as has_position
			from date_range			
        )
        , days as (
            select user_id, day,
                first(type order by created_at) as first_event_type,
                first(position order by created_at) as first_event_position,
                last(type order by created_at) as last_event_type,
                last(position order by created_at) as last_event_position
            from relevant_events
            where (type = 'entry'
                -- exclude short intervals with a synthetic entry from consideration
                and (position is not null or next_time is null or (created_at + '60 seconds'::interval < next_time)))
                or
                (type = 'exit'
                -- exclude short intervals with a synthetic entry from consideration (for data submitted through v2 API)
                and (prev_time is null or prev_pos is not null or (prev_time + '60 seconds'::interval < created_at)))
            group by user_id, day
        )
        , entry_events as (
            select user_id, day,
                min(created_at at time zone (select timezone from projects where id = $1)) as first_entry,
                max(created_at at time zone (select timezone from projects where id = $1)) as last_entry
            from relevant_events
            where type = 'entry'
                -- exclude short intervals with a synthetic entry from consideration
                and (position is not null or next_time is null or (created_at + '60 seconds'::interval < next_time))
            group by user_id, day
        )
        , exit_events as (
            select user_id, day,
                min(created_at at time zone (select timezone from projects where id = $1)) as first_exit,
                max(created_at at time zone (select timezone from projects where id = $1)) as last_exit
            from relevant_events
            where type = 'exit'
                -- exclude short intervals with a synthetic entry from consideration (for data submitted through v2 API)
                and (prev_time is null or prev_pos is not null or (prev_time + '60 seconds'::interval < created_at))
            group by user_id, day
        )
        -- the uploaded positions and events are current to the last sync time
        -- across ALL projects; the sync time for a given project may be behind
        -- the actual data due to moving across projects while offline
        , last_user_sync as (
            select user_id, max(date_trunc('day', synced_at at time zone (select timezone from projects where id = $1))) as day
            from users_projects
            where case when $4 = 0 then true else user_id = $4 end
            group by user_id
        )
		
		select date_range.user_id as id, relevant_users.user_name, relevant_users.user_company, coalesce(nullif(user_roles.name,''), relevant_users.description) as user_role,
			extract(epoch from first_entry)::int as timestamp, to_char(date_range.day, 'DD/MM/YY HH24:MI:SS') as date,

            case when first_event_type = 'entry' then
                to_char(first_entry, 'HH24:MI')
            when first_event_type is null and position_counts.has_position = false then
                'No entry records'
            else
                'On site the night before' end as arrived_at,

            case when first_event_type = 'entry' then first_event_position else null end as first_entry_position,

            --'bla' as departed_at
            case when last_event_type = 'exit' and last_user_sync.day = date_range.day
                then to_char(last_exit, 'HH24:MI') || ' (partial day)'
            when last_event_type = 'exit' and last_user_sync.day > date_range.day
                then to_char(last_exit, 'HH24:MI')
            when last_event_type = 'entry' and last_user_sync.day = date_range.day
                then 'Last known location inside the project at ' ||
                    to_char(		
							(
								select (created_at at time zone (select timezone from projects where id = $1)) from positions
								where project_id = $1 and user_id = date_range.user_id and
								date_trunc('day', created_at at time zone (select timezone from projects where id = $1)) = date_range.day
								order by created_at desc limit 1 -- we use order by desc limit 1 because max(created_at) is very slow
							  )
                        , 'HH24:MI') || ' (partial day)'
            when last_event_type is null and (position_counts.has_position = false
                or date_range.day >= last_user_sync.day) then
                'No exit records'
            else 'On site overnight' end as departed_at,

            case when last_event_type = 'exit' then last_event_position else null end as last_exit_position

        from date_range
        left join days on (days.user_id, days.day) = (date_range.user_id, date_range.day)
        left join position_counts on (position_counts.user_id, position_counts.day) = (date_range.user_id, date_range.day)
        left join last_user_sync on last_user_sync.user_id = date_range.user_id
        left join entry_events on date_range.user_id = entry_events.user_id and date_range.day = entry_events.day
        left join exit_events on date_range.user_id = exit_events.user_id and date_range.day = exit_events.day
        join relevant_users on relevant_users.user_id = date_range.user_id
	join user_roles on relevant_users.role_id = user_roles.id
        where date_range.day <= last_user_sync.day
        order by user_name, date_range.user_id, date_range.day, timestamp
    """
    , req.params.projectId
    , req.query.dateRange[0], req.query.dateRange[1]
    , req.query.userId, (req.query.roleId ? 0)
