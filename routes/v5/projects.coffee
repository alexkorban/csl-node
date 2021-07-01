uid = require "uid-safe"
shared = require "./shared"

calcTimeToBreak = (now, signonEvent, permissions, data) ->
    activePeriodInterval =
        start: coord: 1000 * signonEvent.signonAtUtc
        end: coord: 1000 * signonEvent.periodEndUtc

    scheduledBreakIntervals =
        shared.calcScheduledBreaks activePeriodInterval, data.beaconEvents, data.positions

    getNextBreakTime = (startTime, breakIntervals, permissions) ->
        if R.contains "extended_hours", permissions # Break times claculated from end of last break
            lastBreakTime = R.last(breakIntervals)?.end.coord
            (if lastBreakTime? then Math.round(lastBreakTime / 1000) else startTime) + 6.75 * 60 * 60
        else    # Standard hours - break times calculated from start of day
            startTime + 60 * 60 * (switch breakIntervals.length
                when 0 then 5.25
                when 1 then 7.75
                when 2 then 10.5
                when 3 then 10.75
                else Infinity
            )

    ttb: getNextBreakTime(signonEvent.signonAtUtc, scheduledBreakIntervals.breaks, permissions) - now
    details: scheduledBreakIntervals


#Queries
data =
    getAreaNames: (req) ->
        req.db.master.jsonArrayQuery """
            select geometries.id, type, geometries.properties
            from geometries
            join overlays on overlays.id = geometries.overlay_id
            where project_id = $1 and GeometryType(geometry) = 'POLYGON'
            order by geometries.properties->>'name'
        """
        , req.params.projectId


    getAssets: (req) ->
        req.db.master.jsonArrayQuery """
            select distinct on (beacon_id) id, 'Feature' as type
            , (ST_AsGeoJSON(ST_SetSRID(ST_Point((position->>'lon')::double precision, (position->>'lat')::double precision), 4326)))::json as geometry
            , row_to_json((select props from(select name, description, extract(epoch from created_at)::int as last_time_detected) props)) as properties
            from beacon_events
            where role_id = (select id from beacon_roles where name = 'Asset')
                and type = 'exit'
                and project_id = $1
                and created_at >= now() - interval '30 days'
            order by beacon_id, created_at desc
        """
        , req.params.projectId


geometries =
    getBaseLayers: (req) ->
        req.db.master.jsonArrayQuery """
            select map_id as id, max_zoom, max_native_zoom, display_order, type,
                to_char(updated_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as updated_at
            from base_layers where project_id = $1 and deleted_at = '-infinity'
            order by display_order desc
        """
        , req.params.projectId

    getOverlays: (req) ->
        req.db.master.jsonArrayQuery """
            select id, name, properties, display_order
            from overlays
            where project_id = $1 and deleted_at = '-infinity'
            order by display_order desc
        """
        , req.params.projectId
        .then (overlays) ->
            if req.permissions.drawing
                if easel = R.find R.propEq("name", "User defined areas"), overlays
                    easel.mutable = true

            attachGeometries = (overlay) ->
                req.db.master.jsonArrayQuery """
                    select geometries.id, type, properties, ST_AsGeoJSON(geometry)::json as geometry
                        , to_char(geometries.created_at at time zone (select timezone from projects where id = $1)
                            , 'DD/MM/YY HH24:MI:SS') as created_at
                        , users.name as created_by
                    from geometries
                    left join users on users.id = user_id
                    where overlay_id = $2 and geometries.deleted_at = '-infinity'
                    order by geometries.id
                """
                , req.params.projectId, overlay.id
                .then (geometries) =>
                    R.merge overlay, geometries: geometries

            Promise.all R.map attachGeometries, overlays

notifications =
    createNotification: (req) ->
        req.db.master.query """
            insert into notifications (project_id, geometry_id, type, role_id, user_ids, recipient_ids) values
            ($1, (select geometries.id from geometries
                    join overlays on overlays.id = geometries.overlay_id
                    where project_id = $1 and GeometryType(geometry) = 'POLYGON'
                    order by geometries.properties->>'name' limit 1),
                'entry', (select id from user_roles where name != '' order by name limit 1), '{}', '{}')
        """
        , req.params.projectId

    createRecipient: (req) ->
        req.db.master.query """
                            insert into notifications_recipients (project_id, email) values ($1, $2)
                        """
        , req.params.projectId, req.body.email
        .then ->
            Promise.props
                recipients: notifications.queryRecipients req
                notification: notifications.queryNotification req

    deleteNotification: (req) ->
        req.db.master.query """
            update notifications set deleted_at = now() where id = $1
        """
        , req.params.notificationId

    queryNotification: (req) ->
        req.db.master.jsonQuery """
            select (geometries.properties->>'name') as area, notifications.type, role_id as role,
            recipient_ids as recipients, notifications.id, user_ids as users, is_active
            from notifications
            join geometries on notifications.geometry_id = geometries.id
            where notifications.id = $1
        """
        , req.params.notificationId ?= req.body.notificationId

    queryNotifications: (req) ->
        req.db.master.jsonArrayQuery """
            select (geometries.properties->>'name') as area, notifications.type,
                role_id as role, recipient_ids as recipients,
                notifications.id, user_ids as users, is_active
            from notifications
            join geometries on notifications.geometry_id = geometries.id
            where project_id = $1 and notifications.deleted_at = '-infinity'
            order by area, notifications.created_at desc
        """
        , req.params.projectId

    queryRecipients: (req) ->
        req.db.master.jsonArrayQuery """
            select id, email as name from notifications_recipients
            where project_id = $1
            order by email
        """
        , req.params.projectId

    updateNotification: (req) ->
        q =
            if req.body.action == "replace"
                switch req.body.type
                    when "type" then "set type = $2"
                    when "area" then "set geometry_id = $2"
                    when "role" then "set role_id = $2"
            else
                columnName =
                    switch req.body.type
                        when "users" then "user_ids"
                        when "recipients" then "recipient_ids"
                arrayAction = if req.body.action == "remove" then "array_remove" else "array_append"
                "set #{columnName} = #{arrayAction}((select #{columnName} from notifications where id = $1)::int[], $2)"

        req.db.master.query """
            update notifications #{q}
            where id = $1
        """
        , req.params.notificationId, req.body.itemId

    updateRole: (req) ->
        roleId =
            if req.body.observeesType == "role"
                "(select id from user_roles where name != '' order by name limit 1)"
            else 'null'

        req.db.master.query """
            update notifications set role_id = #{roleId} where id = $1
        """
        , req.params.notificationId
        .then ->
            getRoles =
                req.db.master.jsonArrayQuery "select * from user_roles order by name"

            Promise.props
                roles: getRoles
                notification: notifications.queryNotification req

    updateStatus: (req) ->
        req.db.master.query """
            update notifications set is_active = $1
            where id = $2
        """
        , (req.params.action == "start"), req.params.notificationId

timeline =
    getUsers: (req) ->
        req.db.master.jsonArrayQuery """
            select users.id as id, users.name as name, coalesce(nullif(user_roles.name,''), description) as role, company, null as last_position_at
            from users
            join user_roles on user_roles.id = users.role_id
            where users.id in (
                    select distinct user_id
                    from positions
                    where project_id = $1
                        and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                        (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
                )
            order by role, name
        """
        , req.params.projectId, req.query.date

    getPositionTimeline: (req) ->
        req.db.master.jsonQuery """
            select users.id as user_id, users.name as name, phone_no, company, coalesce(nullif(user_roles.name, ''), description) as role, truck_no, truck_wheel_count
            from users join user_roles on users.role_id = user_roles.id
            where users.id = $1
        """
        , req.query.userId
        .then (user) =>
            req.db.master.jsonArrayQuery """
                select (extract(epoch from created_at) * 1000)::bigint as timestamp,
                    (extract(epoch from lead(created_at, 1)
                        over (order by created_at rows between current row and 1 following)) * 1000)::bigint as next_timestamp,
                    lon, lat, speed, heading

                from positions
                where project_id = $1 and user_id = $2
                    and created_at between (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                           (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
                order by created_at
            """
            , req.params.projectId, req.query.userId, req.query.date
            .then (positions) =>
                # Note: Can't guarantee key order, hence do the manual conversion below to enforce order
                rowToArray = (row) => [row.timestamp, row.nextTimestamp, row.lon, row.lat, row.speed, row.heading]
                R.merge user, positions: R.map rowToArray, positions

    getTimelineInfo: (req) ->
        req.db.master.jsonQuery """
            with time_bounds as (
                select min(created_at) as start, max(created_at) as finish
                from positions
                where project_id = $1
                    and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                           (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
            )
            , intervals as (
                select generate_series((select to_timestamp(floor((extract(epoch from start) / 600 )) * 600) from time_bounds),
                    (select to_timestamp(floor((extract(epoch from finish) / 600 )) * 600) from time_bounds), '10 seconds'::interval) as tick
            )
            , user_counts as (
                select count(distinct user_id) as user_count,
                    to_timestamp(floor((extract(epoch from created_at) / 600 )) * 600) as tick
                from positions
                where created_at between (select start from time_bounds) and (select finish from time_bounds)
                group by tick
            )
            , full_user_counts as (
                select user_count
                from intervals
                left join user_counts on user_counts.tick = intervals.tick
            )
            , agg_user_counts as (
                select array_agg(user_count) as counts from user_counts
            )
            select coalesce(extract(epoch from start), 0) as start,
                coalesce(extract(epoch from finish), 0) as finish,
                (select timezone from projects where id = $1) as time_zone,
                coalesce((select counts from agg_user_counts), '{}') as user_counts
            from time_bounds
        """
        , req.params.projectId, req.query.date

users =
    getUsersQuery: (req) ->
        sortOrder = "name"
        filterFresh = ""
        if req.query.sort? && req.query.sort == "role"
            sortOrder = "role, name"
            filterFresh = """ and users_projects.synced_at > now() - interval '1 month' """

        req.db.master.jsonArrayQuery """
                with user_permissions as (
                    select user_id, array_to_json(array_agg(permission)) as permissions
                    from permissions
                    where project_id = $1 and deleted_at = '-infinity'
                    group by user_id
                )
                select users.id as id, users.name as name, coalesce(nullif(user_roles.name,''), description) as role, company,
                   (select to_char(synced_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS')
                    from users_projects where user_id = users.id and project_id = $1) as last_position_at,
                    coalesce(permissions, '[]'::json) as permissions,
                    user_roles.properties as role_properties
                from users
                join user_roles on user_roles.id = users.role_id
                left join user_permissions on user_permissions.user_id = users.id
                join users_projects on users_projects.user_id = users.id and users_projects.project_id = $1 #{filterFresh}
                order by #{sortOrder}
            """
        , req.params.projectId

    getPavingUsers: (req, res) ->
        if !req.permissions.paving
            return Promise.resolve(null).then -> res.status(403).send "Access denied"

        signonPromise = req.db.master.jsonArrayQuery """
            with vars as (
                select *, start_tstamp at time zone timezone as start_time
                    , start_tstamp + '1 day'::interval - '1 second'::interval as end_tstamp
                    , least(clock_timestamp(),
                        (start_tstamp + '1 day'::interval - '1 second'::interval) at time zone timezone) as end_time
                from (
                    select $1::bigint as project_id
                        , (select timezone from projects where id = $1) as timezone
                        , coalesce($2::timestamp without time zone,
                            date_trunc('day', clock_timestamp() at time zone
                                (select timezone from projects where id = $1))) as start_tstamp
                ) a
            )
            select user_id, max(extract(epoch from created_at)::int) as signon_at_utc
                , extract(epoch from (select end_time from vars))::int as period_end_utc
            from signon_events
            where project_id = (select project_id from vars)
                and created_at >= (select start_time from vars)
                and created_at < (select end_time from vars)
            group by user_id
        """
        , req.params.projectId, req.query.date

        Promise.props {users: users.getUsersQuery(req), signonEvents: signonPromise}
        .then (result) ->
            Promise.all R.map (user) ->
                signonEvent = R.find(R.propEq("userId", user.id), result.signonEvents)
                if (user.role != "Concrete truck" && user.role != "Truck") || !signonEvent?
                    return user    # Can't have a TTB for this user

                beaconEvents = req.db.master.jsonArrayQuery """
                    select first(type) as type, first(1000 * extract(epoch from created_at))::bigint as coord
                    from beacon_events
                    where role_id in (select id from beacon_roles where name = 'Break area')
                        and user_id = $1 and project_id = $2 and type in ('entry', 'exit')
                        and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                    group by beacon_id, type, created_at  -- deal with duplicate records
                    order by created_at, type
                """
                , user.id, req.params.projectId, signonEvent.signonAtUtc, signonEvent.periodEndUtc

                positions = req.db.master.jsonArrayQuery """
                    with break_areas as (
                        select geometry
                        from geometries
                        where overlay_id in (select id from overlays where project_id = $2)
                            and properties->>'purpose' = 'breakArea'
                            and deleted_at = '-infinity'
                    )
                    select (1000 * extract(epoch from created_at))::bigint as coord
                    from positions
                    where user_id = $1 and project_id = $2
                        and exists (select 1 from break_areas
                                    where ST_Contains(geometry, ST_SetSRID(ST_Point(lon, lat), 4326)))
                        and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                    order by created_at
                """
                , user.id, req.params.projectId, signonEvent.signonAtUtc, signonEvent.periodEndUtc

                Promise.props
                    beaconEvents: beaconEvents
                    positions: positions
                .then (userResult) ->
                    ttbRes = calcTimeToBreak signonEvent.periodEndUtc, signonEvent, user.permissions, userResult

                    res = R.merge user, {ttb: ttbRes.ttb, hasSignedOn: true}

                    R.merge res, if req.query.debug?.requests?
                        _signonEvent: signonEvent
                        _beaconEvents: userResult.beaconEvents
                        _positions: userResult.positions
                        _ttbDetails: ttbRes.details
                    else
                        {}
            , result.users

    getPositions: (req) ->
        req.db.master.jsonArrayQuery """
            with recent_positions as (
                select *, row_number() over(partition by user_id order by created_at desc) as index
                from positions
                where project_id = $1 and created_at >= now() - interval '20 minutes'
            )
            select lon, lat, speed, heading,
                to_char(rp.created_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as last_position_at,
                users.id as id, users.name as name, phone_no, company, coalesce(nullif(user_roles.name,''), description) as role, truck_no, truck_wheel_count,

                case when user_roles.name = 'Concrete truck' then
                (
                    with status as (
                        select last(beacon_roles.name order by beacon_events.created_at) = 'Batch plant' as is_loaded
                        from beacon_events
                        join beacon_roles on beacon_events.role_id = beacon_roles.id
                        where ((type = 'exit' and beacon_roles.name = 'Batch plant') or (type = 'entry' and beacon_roles.name = 'Paver'))
                        and beacon_events.project_id = $1
                        and beacon_events.user_id = rp.user_id
                        and beacon_events.created_at at time zone (select timezone from projects where id = $1)
                                                     >= date_trunc('day', clock_timestamp() at time zone (select timezone from projects where id = $1))
                    ) select coalesce(is_loaded, false) from status
                )
                else false
                end as is_loaded,

                case when (user_roles.properties->>'is_machine')::boolean then
                    (select coalesce(json_agg(r), '[]') from (select lon, lat, speed, heading, index,
                        to_char(created_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as created_at
                     from recent_positions
                     where recent_positions.user_id = rp.user_id and index > 1
                        and recent_positions.created_at >= now() - interval '5 minutes' order by index) r
                    )::json
                    else '[]'::json
                end as trail,

                (user_roles.properties->>'does_paving')::boolean as does_paving
            from recent_positions rp, users join user_roles on users.role_id = user_roles.id
            where index = 1 and users.id = rp.user_id
            order by user_id
        """
        , req.params.projectId

    getRoles: (req) ->
        if req.query.getAll
            req.db.master.jsonArrayQuery "select * from user_roles where name != '' order by name"
        else
            req.db.master.jsonArrayQuery """
                select *
                from user_roles
                where id in (
                    select distinct role_id from users where id in (
                        select distinct user_id from events where project_id = $1
                    )
                )
                and name != ''
                order by name
            """
            , req.params.projectId

    getUserAppConfigs: (req, res) ->
        if req.permissions.hr
            req.db.master.jsonArrayQuery """
                select distinct on (info_events.user_id) info_events.user_id as id, info_events.properties as app_config
                    , (users.push_id is not null) as has_push_id
                from info_events
                join users on user_id = users.id
                where type = 'diagnostics'
                    and user_id in (select user_id from users_projects where users_projects.project_id = $1
                                    and users_projects.synced_at > now() - interval '1 month')
                order by info_events.user_id, info_events.created_at desc
            """
            , req.params.projectId
            .then (users) ->
                R.mergeAll R.map (user) ->
                    diagnosticKeys = ["bluetoothOn", "gpsOn", "os", "version"]
                    storeKeys = ["beaconScanFreq", "positionFreq", "positionFreqACEnabled"]
                    appConfig = R.mergeAll [
                        hasPushId: user.hasPushId
                        (R.pick diagnosticKeys, user.appConfig)
                        (R.pick storeKeys, user.appConfig.storedState)
                    ]

                    "#{user.id}": appConfig
                , users
        else
            Promise.resolve(null).then -> res.status(403).send "Access denied"

vehicles =
    getPositions: (req) ->
        req.db.master.jsonArrayQuery """
            with vars as (
                select *, start_tstamp at time zone timezone as start_time
                    , least(clock_timestamp(),
                        (start_tstamp + '1 day'::interval - '1 second'::interval) at time zone timezone)
                        as end_time
                from (
                    select $1::bigint as project_id
                        , (select timezone from projects where id = $1) as timezone
                        , coalesce($2::timestamp without time zone,
                            date_trunc('day', clock_timestamp() at time zone
                                (select timezone from projects where id = $1))) as start_tstamp
                ) a
            )
            select vehicles.id as id, beacon_id, number, make, model, rego, vehicle_roles.name as role
                , extract(epoch from (select start_time from vars))::int as start_time_utc
                , extract(epoch from (select end_time from vars))::int as end_time_utc
                , '[]'::json as trail
            from vehicles
            join vehicle_roles on vehicle_roles.id = vehicles.role_id
            where beacon_id is not null
                and customer_id = (select customer_id from projects where id = $1)
        """
        , req.params.projectId, req.query.date
        .then (vehicles) ->
            Promise.all R.map (vehicle) ->
                # To reduce the amount of calculations, first try to get the position using today's data and
                # filtering out short beacon intervals
                req.db.master.jsonQuery """
                    with intervals as (
                        select beacon_id, user_id, type, created_at
                            , (lead (position, 1) over (partition by user_id order by created_at)) as position
                            , (lead (type, 1) over (partition by user_id order by created_at)) as next_type
                            , (lead (created_at, 1) over (partition by user_id order by created_at)) as next_created_at
                        from beacon_events
                        where beacon_id = $2
                            and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                    ),
                    v_position as (
                        select case next_type
                            when 'exit' then coalesce (
                                intervals.position,
                                (select row_to_json(t) from
                                    (select lon, lat, created_at
                                     from positions
                                     where user_id = intervals.user_id
                                        and created_at <= (intervals.position->>'created_at')::timestamp
                                     order by created_at desc limit 1
                                    ) t
                                ))
                            else (select row_to_json(t) from
                                      (select lon, lat, created_at
                                       from positions
                                       where user_id = intervals.user_id order by created_at desc limit 1) t)
                            end as position
                        from intervals
                        where type = 'entry'
                            and ((next_type is null) or next_created_at - intervals.created_at >= '10 sec')
                        order by next_type desc, intervals.created_at desc limit 1
                    )
                    select (position->>'lon')::double precision as lon
                        , (position->>'lat')::double precision as lat
                        , to_char(((position->>'created_at')::timestamp with time zone)
                            at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS')
                            as last_position_at
                    from v_position
                """
                , req.params.projectId, vehicle.beaconId, vehicle.startTimeUtc, vehicle.endTimeUtc
                .then (todayPosition) ->
                    # If we couldn't establish the position using today's data, try to get it from older beacon events
                    # using a simplified calculation
                    if R.isEmpty todayPosition
                        req.db.master.jsonQuery """
                            with v_position as (
                                select coalesce(
                                    position
                                    , (select row_to_json(t) from
                                           (select lon, lat, created_at
                                            from positions
                                            where user_id = beacon_events.user_id
                                                and created_at <= beacon_events.created_at
                                            order by created_at desc limit 1) t)
                                ) as position
                                from beacon_events
                                where beacon_id = $2 and type = 'exit'
                                    and created_at >= (to_timestamp($3) - interval '6 days')
                                    and created_at < to_timestamp($3)
                                order by created_at desc limit 1
                            )
                            select (position->>'lon')::double precision as lon
                                , (position->>'lat')::double precision as lat
                                , to_char(((position->>'created_at')::timestamp with time zone)
                                    at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS')
                                    as last_position_at
                            from v_position
                        """
                        , req.params.projectId, vehicle.beaconId, vehicle.startTimeUtc
                    else
                        todayPosition
                .then (position) ->
                    R.merge vehicle, position
            , vehicles
            .then (rows) ->
                R.reject ((row) -> R.isEmpty(row) || !row.lastPositionAt?), rows


    getVehicleRoles: (req) ->
        req.db.master.jsonArrayQuery "select * from vehicle_roles where name != '' order by name"


    getVehicles: (req) ->
        req.db.master.jsonArrayQuery """
            select id, number, model, make
            from vehicles
            where customer_id = (select customer_id from projects where id = $1)
            order by number
        """
        , req.params.projectId



hrAuthorised = (req) ->
    req.permissions.hr && (req.permissions.permittedProjects == "all" || R.contains req.params.projectId, req.permissions.permittedProjects)


withHrAuthorisation = (req, res, reqHandler) ->
    if hrAuthorised req
        reqHandler()
    else
        Promise.resolve(null).then -> res.status(403).send "Access denied"


module.exports = (helpers) ->
    getAll: helpers.withErrorHandling (req, res) ->
        projects = req.permissions.permittedProjects
        if !R.isEmpty projects
            req.db.master.jsonQuery """
                select customer_id from users_hq where id = $1
            """
            , req.session.data.userId
            .then (result) ->
                inClause =
                    if projects == "all"
                        "and customer_id = #{result.customerId}"
                    else
                        "and id in (#{projects.join()})"
                q = """
                    select id, name, timezone, created_at, updated_at
                        , ST_AsGeoJson(ST_FlipCoordinates(ST_Envelope(download_boundary)))::json as bbox_points
                        , ST_AsGeoJson(ST_FlipCoordinates(ST_Centroid(download_boundary)))::json as centroid
                        , (properties->>'show_users_panel')::boolean as show_users_panel
                    from projects
                    where deleted_at = '-infinity'
                          #{inClause}
                    order by name
                """
                req.db.master.jsonArrayQuery q
                .then (result) ->
                    res.json result
        else
            res.json []

    data:
        getAreas: helpers.withErrorHandling (req, res) ->
            data.getAreaNames(req).then (result) ->
                res.json result

        getAssets: helpers.withErrorHandling (req, res) ->
            data.getAssets(req).then (result) ->
                res.json result

    geometries:
        saveGeometry: helpers.withErrorHandling (req, res) ->
            req.db.master.jsonQuery """
                select id from overlays where name = $1 and project_id = $2
            """
            , "User defined areas"
            , req.params.projectId
            .then (overlay) ->
                req.logs.messages.push "User defined overlay id: #{overlay.id}"

                if req.body.id?
                    req.db.master.query """
                        update geometries
                        set geometry = ST_SetSRID(ST_GeomFromGeoJSON($1), 4326), properties = $2, updated_at = clock_timestamp()
                        where id = $3
                    """
                    , (JSON.stringify req.body.geometry)
                    , (JSON.stringify req.body.properties)
                    , req.body.id
                    .then ->
                        res.json {}
                else
                    req.db.master.query """
                        insert into geometries (geometry, properties, overlay_id)
                        values (ST_SetSRID(ST_GeomFromGeoJSON($1), 4326), $2, $3)
                        returning id
                    """
                    , (JSON.stringify req.body.geometry)
                    , (JSON.stringify req.body.properties)
                    , overlay.id
                    .then (result) ->
                        res.json id: result.rows[0].id

        deleteGeometry: helpers.withErrorHandling (req, res) ->
            req.db.master.query "update geometries set deleted_at = clock_timestamp() where id = $1"
            , req.params.geometryId
            .then ->
                res.json {}

        getBaseLayers: helpers.withErrorHandling (req, res) ->
            geometries.getBaseLayers(req, res).then (result) ->
                res.json result

        getOverlays: helpers.withErrorHandling (req, res) ->
            geometries.getOverlays(req, res).then (result) ->
                res.json result

    timeline:
        get: helpers.withErrorHandling (req, res) ->
            timeline.getTimelineInfo(req, res).then (result) ->
                res.json result
        getPositionTimeline: helpers.withErrorHandling (req, res) ->
            timeline.getPositionTimeline(req, res).then (result) ->
                res.json result

    users:
        getPavingUsers: helpers.withErrorHandling (req, res) ->
            users.getPavingUsers(req, res).then (result) ->
                res.json result
        getPositions: helpers.withErrorHandling (req, res) ->
            users.getPositions(req, res).then (result) ->
                res.json result
        getRoles: helpers.withErrorHandling (req, res) ->
            users.getRoles(req, res).then (result) ->
                res.json result
        getUsers: helpers.withErrorHandling (req, res) ->
            if req.query.date?      # Timeline request
                timeline.getUsers(req).then (result) ->
                    res.json result
            else
                users.getUsersQuery(req, res).then (result) ->
                    res.json result
        getUserAppConfigs: helpers.withErrorHandling (req, res) ->
            users.getUserAppConfigs(req, res).then (result) ->
                res.json result


    createPermissions: helpers.withErrorHandling (req, res) ->
        if !req.body.cslToken? || req.body.cslToken != process.env.CSL_ADMIN_TOKEN
            res.status(403).send "Authentication failed"
            return

        req.db.master.jsonQuery """
            select count(permission) as count from project_creds where project_id = $1
        """
        , req.params.projectId
        .then (existingCreds) ->
            console.log "Existing creds:", existingCreds
            if existingCreds.count > 0
                res.status(403).send "Project creds already exist"
                return

            createPermission = (permission) ->
                req.logs.messages.push "Processing permission #{permission}"
                cred = uid.sync 18
                bcrypt.hashAsync(cred, 10)
                .then (bcryptedCred) ->
                    req.db.master.query """
                        insert into project_creds(project_id, permission, cred_hash) values ($1, $2, $3)
                    """, req.params.projectId, permission, bcryptedCred
                .then ->
                    req.logs.messages.push "Got cred #{cred}"
                    result = {}
                    result[permission] = cred
                    result

            req.logs.messages.push "Processing credentials"
            Promise.all R.map createPermission, req.body.permissions
            .then (result) ->
                res.json result
                
    notifications: 
        getAll: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.queryNotifications(req).then (result) ->
                    res.json result

        getNotification: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.queryNotification(req).then (result) ->
                    res.json result

        getRecipients:  helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.queryRecipients(req).then (result) ->
                    res.json result

        createRecipient:  helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                req.db.master.jsonQuery """
                    select id from notifications_recipients where project_id = $1 and email = $2
                """
                , req.params.projectId, req.body.email
                .then (email) ->
                    if R.isEmpty email
                        notifications.createRecipient(req).then (result) ->
                            res.json result
                    else res.json {}

        create: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.createNotification req
                .then ->
                    notifications.queryNotifications req
                .then (result) ->
                    res.json result

        update: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.updateNotification(req).then ->
                    res.json {}

        delete: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.deleteNotification(req).then ->
                    res.json {}

        updateStatus: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.updateStatus(req).then ->
                    res.json {}

        updateRole: helpers.withErrorHandling (req, res) ->
            withHrAuthorisation req, res, ->
                notifications.updateRole(req).then (result) ->
                    res.json result

    vehicles:
        getPositions: helpers.withErrorHandling (req, res) ->
            vehicles.getPositions(req).then (result) ->
                res.json result

        getVehicleRoles: helpers.withErrorHandling (req, res) ->
            vehicles.getVehicleRoles(req).then (result) ->
                res.json result

        getVehicles: helpers.withErrorHandling (req, res) ->
            vehicles.getVehicles(req).then (result) ->
                res.json result

    _calcTimeToBreak: calcTimeToBreak


