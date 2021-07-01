# Take only entry-exit intervals
takeAreaEntryExitIntervals =
    R.filter (interval) -> interval.start.type == "entry" && interval.end.type == "exit"


# Take |-exit, entry-exit & entry-| intervals
takeVisitIntervals =
    R.filter (interval) -> interval.start.type == "entry" || interval.end.type == "exit"


convertToVisitRecords = R.map (interval) ->
    entryAt: interval.start.coord
    exitAt: interval.end.coord
    length: Series.Interval.length interval


getTotalTimeInArea = R.pipe takeVisitIntervals
    , R.map(Series.Interval.length)
    , R.sum


calcAreaVisits = (userDay, areaEvents, params, req) ->
    activePeriodInterval =
        start: coord: userDay.dayStartUtc
        end: coord: userDay.dayEndUtc

    debugData = {}

    req?.logs.messages.push "constructing area intervals"

    getAreaIntervals = R.pipe Series.makeSeries([activePeriodInterval])
    ,           util.takePipeSample("_areaEventsSeries", params.debug?.requests, debugData)
    , Series.getPointIntervals

    areaIntervals = getAreaIntervals areaEvents

    convertAreaIntervalsIntoVisits = R.pipe takeAreaEntryExitIntervals
    ,           util.takePipeSample("_entryExitIntervals", params.debug?.requests, debugData)
    , convertToVisitRecords

    req?.logs.messages.push "composing response"
    res =
        areaName: areaEvents[0].areaName
        isBoundary: areaEvents[0].isBoundary
        areaVisits: convertAreaIntervalsIntoVisits areaIntervals
        totalTime: getTotalTimeInArea areaIntervals
        firstEntryMissing: R.head(areaEvents).type == "exit"
        lastExitMissing: R.last(areaEvents).type == "entry"

    if params.debug
        debugData = R.merge debugData, _areaEvents: areaEvents
    else
        # Do nothing - no debug data
        R.merge res, debugData


module.exports = (req) ->
    req.db.follower.jsonArrayQuery """
        with relevant_users as (
            select users.id as user_id, user_roles.name as user_role, users.name as user_name
                , users.company as user_company
                , (select max(synced_at) from users_projects
                    where users_projects.user_id = users.id) as last_synced_at
            from users
            join user_roles on users.role_id = user_roles.id
            join users_projects on users.id = user_id and users_projects.project_id = $1
            where (case when $4 = 0 then true else users.id = $4 end)
                and (case when $5 = 0 then true else user_roles.id = $5 end)
        )
        select day, user_id, user_name, user_role, user_company
            , last_synced_at at time zone (select timezone from projects where id = $1) as last_synced_at
            , (1000 * extract(epoch from day at time zone
                (select timezone from projects where id = $1)))::bigint as day_start_utc
            , (1000 * extract(epoch from least(clock_timestamp(), day at time zone
                (select timezone from projects where id = $1)
                    + '1 day'::interval - '1 second'::interval)))::bigint as day_end_utc
            , (last_synced_at > day at time zone (select timezone from projects where id = $1)
                    + '1 day'::interval - '1 second'::interval) as has_synced_on_later_date
            , day at time zone (select timezone from projects where id = $1)
                    + '1 day'::interval - '1 second'::interval as day_end_local
        from relevant_users
        cross join (select generate_series(($2::timestamp without time zone),
                                           ($3::timestamp without time zone), '1 day') as day) dates
    """
    , req.params.projectId, req.query.dateRange[0], req.query.dateRange[1]
    , (req.query.userId ? 0), (req.query.roleId ? 0)
    .then (userDays) ->
        Promise.all R.map (userDay) ->
            req.db.follower.jsonArrayQuery """
                with areas as (
                    select geometries.properties->>'name' as area_name, geometries.id as area_id
                        , coalesce((overlays.properties->>'is_boundary')::bool, false) as is_boundary
                    from geometries
                    join overlays on overlays.id = geometries.overlay_id
                    where (case when $1 = 0 then geometries.id in
                                (select id from geometries where overlay_id in
                                    (select id from overlays where project_id = $2))
                            else geometries.id = $1 end)
                )
                select areas.*, type, (1000 * extract(epoch from created_at))::bigint as coord
                from events
                join areas on area_id = geometry_id
                where events.type in ('entry', 'exit') and events.user_id = $3
                    and events.created_at >= $4::timestamp
                        at time zone (select timezone from projects where id = $2)
                    and events.created_at < $4::timestamp
                        at time zone (select timezone from projects where id = $2) + '1 day'::interval
                order by area_id, created_at
            """
            , (req.query.geometryId ? 0), req.params.projectId, userDay.userId, userDay.day
            .then (entryExitEvents) ->
                areasDetails = R.map (areaEvents) ->
                    calcAreaVisits userDay, areaEvents, req.query, req
                , R.groupWith(R.eqProps("areaId"), entryExitEvents)
                R.merge userDay, areasDetails: areasDetails
        , userDays
    .then (userDays) ->
        R.reject ((userDay) -> R.isEmpty userDay.areasDetails), userDays
