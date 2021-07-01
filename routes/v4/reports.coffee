shared = require "./shared"

getDriverDays = (req) ->
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


# (a -> b) -> [a] -> [b] -> Bool
equalBy = R.curry (eqFunc, a, b) ->
    R.pipe(R.zipWith(R.eqBy eqFunc), R.all(R.identity)) a, b


MIN_PROXIMITY_INTERVAL =
    load: 59 * 1000 # ms
    dump: 39 * 1000 # ms
MAX_PROXIMITY_GAP =
    load: 3 * 60 * 1000 # ms
    dump: 1 * 60 * 1000 # ms

takeEntryExitIntervals = R.filter (interval) ->
    isLoadInterval = interval.start.type == "load_entry" && interval.end.type == "load_exit"
    isDumpInterval = interval.start.type == "dump_entry" && interval.end.type == "dump_exit"
    isLoadInterval || isDumpInterval

dropShortIntervals = R.reject (interval) ->
    Series.Interval.length(interval) < MIN_PROXIMITY_INTERVAL[intervalType interval]

takeLoadDumpIntervals =
    R.filter (intervalPair) ->
        intervalPair[0].start.type == "load_entry" && intervalPair[1].start.type == "dump_entry"

# [[SeriesPointInterval, SeriesPointInterval]] -> [[SeriesPointInterval, SeriesPointInterval]]
annotateNextLoadTime = (loadDumps) ->
    return [] if R.isEmpty loadDumps
    R.pipe(R.aperture(2)
    , R.map((pairOfLoadDumps) ->
        load = R.merge(pairOfLoadDumps[0][0], nextLoadStartsAt: pairOfLoadDumps[1][0].start.coord)
        [load, pairOfLoadDumps[0][1]]
    )
    , R.append(R.last loadDumps)) loadDumps  # Last loadDump doesn't have nextLoadStartsAt
                                             # (as it isn't a complete cycle)

isStopInterval = (interval) ->
    interval.end.type == "move" || (interval.start.type == "stop" && !interval.end.type?)


recombineAperturePairs = (aperturePairs) ->
    R.pipe(R.init, R.map(R.head), R.concat(R.__, R.last(aperturePairs))) aperturePairs


adjustIntervalsToOverlapMidpoints = (intervals) ->
    return intervals if intervals.length < 2

    adjust = R.map (pair) ->
        return pair if pair.length < 2 # If the source array has odd length, we can get a single element array here

        if pair[0].end.coord > pair[1].start.coord
            newPair = R.clone pair
            overlapMidpoint = pair[1].start.coord + Math.round((pair[0].end.coord - pair[1].start.coord) / 2)
            newPair[0].end.coord = overlapMidpoint
            newPair[1].start.coord = overlapMidpoint + 1
            # When the first interval fully overlaps the second one, it can push the start of the second interval
            # past its end, so the end coord may need to be adjusted. If it's adjusted, we produce an improper
            # interval. We keep it (instead of throwing it away completely) in order to preserve the length of
            # the interval array
            newPair[1].end.coord = Math.max newPair[1].start.coord, newPair[1].end.coord
            newPair
        else
            pair

    # First pass: adjust overlaps between 1-2, 3-4 etc.
    newIntervals = R.pipe(R.splitEvery(2), adjust, R.flatten) intervals

    # Second pass: adjust overlaps between (already half-adjusted) 2-3, 4-5 etc.
    R.pipe(R.tail, R.splitEvery(2), adjust, R.flatten, R.prepend(R.head newIntervals)) newIntervals


getQueueingTime = (interval, movementEvents) ->
    #logs?.messages.push "calculating queueing time"
    R.pipe(Series.makeSeries([interval])
    , Series.getPointIntervals
    , R.filter(isStopInterval)
    , R.map(Series.Interval.length)
    , R.sum) movementEvents

getDistance = (interval, positions) ->
    #logs?.messages.push "calculating distance"
    R.pipe(R.filter(Series.Interval.contains(R.__, interval))
    , R.map(R.prop("distance"))
    , R.sum) positions

calcFuelBurn = (driveDistance, idleTime) ->
    (driveDistance / 1000) * 0.33 + moment.duration(idleTime).asHours() * 3.7


# Array<Interval> (no adjacent intervals for the same area) -> Interval
reduceToSingleDump = (intervals) ->
    ambiguousDumpPlaceholder = (intervals) ->
        names = R.uniq R.map R.path(["start", "name"]), intervals
        matchesUserFilter = R.any R.path(["start", "matchesUserFilter"]), intervals
        dumpTimes = R.map R.path(["end", "coord"]), intervals
        dumpedAt = Math.max dumpTimes...  # Take the latest possible dump time

        isAmbiguousPlaceholder: true
        possibleAreaNames: names
        start: {type: "dump_entry", matchesUserFilter: matchesUserFilter}
        end: {type: "dump_exit", coord: dumpedAt}

    if intervals.length % 2 == 1
        middle = Math.floor(intervals.length / 2)
        haulSeq = R.slice(0, middle, intervals)
        returnSeq = R.reverse R.slice(-middle, intervals.length, intervals)
        if equalBy R.path(["start", "areaId"]), haulSeq, returnSeq
            intervals[middle]
        else
            ambiguousDumpPlaceholder intervals
    else
        ambiguousDumpPlaceholder intervals


# Interval -> String
intervalType = (interval) -> if interval.start.type == "load_entry" then "load" else "dump"


# {load: Int, dump: Int} -> Interval -> Interval -> Interval
isSameVisit = R.curry (maxGapAllowed, left, right) ->
    left.start.areaId == right.start.areaId && right.start.coord - left.end.coord < maxGapAllowed[intervalType left]


# Ensure there are no adjacent intervals with the same area ID, which then allows to pick a single dump site
# [Interval] (2+ elements) -> [Interval]
normaliseDumpSubsequence =
    # joinOverSameVisit requires a value for each interval type, even though here we're applying it to dumps only
    R.pipe Series.joinIntervals(isSameVisit {load: 60 * 60 * 1000, dump: 60 * 60 * 1000}), reduceToSingleDump, Array

# [Interval] -> [Interval]
normaliseSubsequence = R.curry (missingDumpsAllowed, intervals) ->
    if intervals.length > 1
        if intervals[0].start.type == "load_entry"
            if missingDumpsAllowed
                missingDumpPlaceholder =
                    isMissingPlaceholder: true
                    start: {type: "dump_entry", matchesUserFilter: true}
                    end: {type: "dump_exit"}
                R.intersperse missingDumpPlaceholder, intervals
            else
                R.takeLast 1, intervals
        else  # dump_entry
            normaliseDumpSubsequence intervals
    else
        intervals

# Turns an arbitrary sequence of L & D events into (L(D|D'|D''))+L{0,1},
# where D' is a missing dump & D'' is an ambiguous dump location
# [Interval] -> [Interval]
normaliseDumpIntervals = R.curry (missingDumpsAllowed, intervals) ->
    R.pipe(R.dropWhile(R.pathEq(["start", "type"], "dump_entry"))  # Drop initial dumps - no sense without a load
    , R.groupWith(R.eqBy(R.path(["start", "type"])))               # Group by load/dump
    , R.chain(normaliseSubsequence missingDumpsAllowed)) intervals


buildCycles = R.curry (logs, data, loadDumpPairs) ->
    #logs?.messages.push "calculating cycle details"

    R.map (loadDumpPair) ->
        [load, dump] = loadDumpPair
        isCycle = load.nextLoadStartsAt?
        isValidDump = !dump.isMissingPlaceholder? && !dump.isAmbiguousPlaceholder?

        haulInterval =
            start: coord: load.end.coord
            end: coord: dump.start.coord

        returnInterval =
            start: coord: dump.end.coord
            end: coord: load.nextLoadStartsAt

        loadTime = Series.Interval.length load
        dumpTime = if isValidDump then Series.Interval.length dump else null
        haulTime = if isValidDump then Series.Interval.length haulInterval else null
        haulDistance = if isValidDump then getDistance(haulInterval, data.driverDistances) else null
        returnTime = if isCycle && isValidDump then Series.Interval.length returnInterval else null
        returnDistance = if isCycle && isValidDump then getDistance(returnInterval, data.driverDistances) else null

        loadedQueueingTime = if isValidDump then getQueueingTime(haulInterval, data.movementEvents) else null
        emptyQueueingTime = if isCycle && isValidDump then getQueueingTime(returnInterval, data.movementEvents) else null
        idleTime = loadTime + (dumpTime ? 0) + (loadedQueueingTime ? 0) + (emptyQueueingTime ? 0)

        loadedAt: load.start.coord
        loadTime: loadTime
        loadedBy: load.start.name
        isMissingDump: dump.isMissingPlaceholder?
        isAmbiguousDump: dump.isAmbiguousPlaceholder?
        haulTime: haulTime
        haulDistance: haulDistance
        loadedQueueingTime: loadedQueueingTime
        dumpTime: dumpTime
        dumpedAt: if !dump.isMissingPlaceholder? then dump.end.coord else null
        dumpedIn: if isValidDump then dump.start.name else (dump.possibleAreaNames ? null)
        returnTime: returnTime
        returnDistance: returnDistance
        emptyQueueingTime: emptyQueueingTime
        cycleTime: if isCycle then load.nextLoadStartsAt - load.start.coord else null
        fuelBurn: if isValidDump then calcFuelBurn(haulDistance + (returnDistance ? 0), idleTime) else null
    , loadDumpPairs



calcDayLoadCounts = (driverDay, data, params, logs) ->
    activePeriodInterval =
        start: coord: 1000 * driverDay.dayStartUtc
        end: coord: 1000 * driverDay.dayEndUtc

    logs?.messages.push "in calcDayLoadCounts"

    debugData = {}

    getEntryExits = R.pipe Series.makeSeries([activePeriodInterval]), Series.getPointIntervals, takeEntryExitIntervals

    convertProximityEventsIntoCycles = R.pipe R.groupWith(R.eqProps "areaId")  # Split into streams by area
        , R.map(getEntryExits)   # Find entry-exits
        ,                               util.takePipeSample("_entryExitIntervals", params.debug?.requests, debugData)
        , R.flatten   # Recombine
        , R.sortBy(R.path ["start", "coord"])   # Order by interval start
        ,                               util.takePipeSample("_sortedIntervals", params.debug?.requests, debugData)
        , Series.joinIntervals(isSameVisit MAX_PROXIMITY_GAP)
        , dropShortIntervals
        , adjustIntervalsToOverlapMidpoints
        ,                               util.takePipeSample("_preparedIntervals", params.debug?.requests, debugData)
        , normaliseDumpIntervals(!driverDay.isSpecificDumpArea)
        ,                               util.takePipeSample("_normalisedIntervals", params.debug?.requests, debugData)
        , R.aperture(2)
        , takeLoadDumpIntervals
        ,                               util.takePipeSample("_loadDumpPairs", params.debug?.requests, debugData)
        , R.filter(R.all R.path ["start", "matchesUserFilter"])
        , annotateNextLoadTime
        , buildCycles(logs, data)

    cycles = convertProximityEventsIntoCycles data.proximityEvents

    logs?.messages.push "converted proximity events into cycles"

    res = R.merge driverDay, cycles: cycles

    if params.debug?.requests
        debugData = R.merge debugData,
            _movementEvents: data.movementEvents
            _proximityEvents: data.proximityEvents
            _driverDistances: data.driverDistances
            userName: "#{res.userName} (#{res.userId})"
    else
        # Do nothing - no debug data

    R.merge res, debugData


calcAreaVisits = (userDay, areaEvents, params, req) ->
    activePeriodInterval =
        start: coord: userDay.dayStartUtc
        end: coord: userDay.dayEndUtc

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


handlers =
    getProjectVisits: (req, res) ->
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
            , date_range as (  -- every date in the selected range for every selected user
                select day, users.id as user_id
                from users
                join user_roles on users.role_id = user_roles.id
                cross join (select generate_series(($2::timestamp without time zone),
                                                   ($3::timestamp without time zone), '1 day') as day) dates
                where case when $4 = 0 then users.id in (select distinct user_id from events where project_id = $1) else users.id = $4 end  -- any user or specific user
                    and (case when $5 = 0 then true else user_roles.id = $5 end)
            )
            , position_counts as (
                select date_trunc('day', positions.created_at at time zone (select timezone from projects where id = $1)) as day,
                    user_id, count(*) as count
                from positions
                join users on positions.user_id = users.id
                join user_roles on users.role_id = user_roles.id
                where positions.project_id = $1
                    and (case when $4 = 0 then true else user_id  = $4 end)
                    and (case when $5 = 0 then true else user_roles.id = $5 end)
                    and positions.created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                                     (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1) + '1 day'::interval - '1 second'::interval)
                group by user_id, date_trunc('day', positions.created_at at time zone (select timezone from projects where id = $1))
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
            select date_range.user_id as id, users.name as user_name, users.company as user_company, coalesce(nullif(user_roles.name,''), users.description) as user_role,
                extract(epoch from first_entry)::int as timestamp, to_char(date_range.day, 'DD/MM/YY HH24:MI:SS') as date,

                case when first_event_type = 'entry' then
                    to_char(first_entry, 'HH24:MI')
                when first_event_type is null and (position_counts.count is null or position_counts.count = 0) then
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
                            (select max(created_at at time zone (select timezone from projects where id = $1)) from positions
                             where project_id = $1 and user_id = date_range.user_id and
                                date_trunc('day', created_at at time zone (select timezone from projects where id = $1)) = date_range.day)
                            , 'HH24:MI') || ' (partial day)'
                when last_event_type is null and (position_counts.count is null or position_counts.count = 0
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
            join users on users.id = date_range.user_id
            join user_roles on users.role_id = user_roles.id
            where date_range.day <= last_user_sync.day
            order by user_name, date_range.user_id, date_range.day, timestamp
        """
        , req.params.projectId
        , req.query.dateRange[0], req.query.dateRange[1]
        , req.query.userId, (req.query.roleId ? 0)


    getAreas: (req, res) ->
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


    getSpeedBands: (req, res) ->
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


    getTimeline: (req, res) ->
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


    getConcreteTests: (req, res) ->
        req.db.follower.jsonArrayQuery """
            with report_events as (
               select *, properties->>'docket_id' as docket_id
               from events
               where type = 'concrete_movement' and project_id = $1
               and created_at between (($2::timestamp without time zone) at time zone (select timezone from projects where id = $1)) and
                                      (($3::timestamp without time zone) at time zone (select timezone from projects where id = $1)
                                            + '1 day'::interval - '1 second'::interval)
            )
            , load_events as (
               select user_id, docket_id, created_at as loaded_at, position as load_position,
                   properties->'docket_details' as docket_details
               from report_events
               where properties->>'step' = 'load'
            )
            , test_events as (
               select user_id, docket_id, created_at as tested_at, position as test_position,
                   properties->'docket_details' as docket_details, properties->'test_details' as test_details
               from report_events
               where properties->>'step' = 'test'
            )
            , dump_events as (
               select user_id, docket_id, created_at as dumped_at, position as dump_position,
                   properties->'docket_details' as docket_details, properties as dump_properties
               from report_events
               where properties->>'step' = 'dump'
            )
            , dockets as (
		        select distinct docket_id
		        from report_events
                where properties->>'step' != 'invalid'
            )
            , valid_events as (
                select
                    coalesce(te.user_id, le.user_id, de.user_id) as user_id, docket_id,
                    -- load event
                    loaded_at, load_position,
                    coalesce(le.docket_details, te.docket_details, de.docket_details)->>'batch_plant_name' as batch_plant_name,
                    coalesce(le.docket_details, te.docket_details, de.docket_details)->>'load_number' as load_number,
                    coalesce(le.docket_details, te.docket_details, de.docket_details)->>'mix_code' as mix_code,
                    coalesce(le.docket_details, te.docket_details, de.docket_details)->>'date_time_string' as batch_time,
                    coalesce(le.docket_details, te.docket_details, de.docket_details)->>'load_volume' as load_volume,
                    -- test event
                    tested_at, test_position, test_details,
                    -- dump event
                    dumped_at, dump_position, dump_properties
                from dockets
                left join load_events le using(docket_id)
                left join test_events te using(docket_id)
                left join dump_events de using(docket_id)
            )
            , invalid_events as (
                select user_id, null::text as docket_id,
                    -- mock load event
                    case when properties->>'selected_step' = 'load' then created_at else null end as loaded_at,
                    position as load_position,
                    null::text as batch_plant_name,
                    null::text as load_number,
                    null::text as mix_code,
                    null::text as batch_time,
                    null::text as load_volume,
                    -- mock test event
                    case when properties->>'selected_step' = 'test' then created_at else null end as tested_at,
                    position as test_position,
                    null::json as test_details,
                    -- mock dump event
                    case when properties->>'selected_step' = 'dump' then created_at else null end as dumped_at,
                    position as dump_position,
                    null::json as dump_properties,
                    -- error details
                    (properties->>'selected_step')::text as error_step,
                    (properties->>'scan_text')::text as error_text
                from report_events where properties->>'step' = 'invalid'
            )
            , combined_events as (
                select *,
                    ''::text as error_step, ''::text as error_text -- no error
                from valid_events
                union all
                select * from invalid_events
            )
            select
                load_position, test_position, dump_position,
                error_step, error_text,
                docket_id, users.name as user_name,
                load_position, test_position, dump_position,
                batch_plant_name, load_number, mix_code, batch_time, load_volume,
                test_details->>'type' as test_type,
                (test_details->>'initial_slump')::int as initial_slump,
                (test_details->>'final_slump')::int as final_slump,
                (test_details->>'air_content1')::numeric as air_content1,
                (test_details->>'air_content2')::numeric as air_content2,
                (test_details->>'air_correction')::numeric as air_correction,
                (test_details->>'muv')::int as muv,
                (test_details->>'air_temp')::int as air_temp,
                (test_details->>'concrete_temp')::int as concrete_temp,
                test_details->>'cylinder_num' as cylinder_num,
                test_details->>'beam_num' as beam_num,
                test_details->>'notes' as notes,
                coalesce(dump_properties#>>'{inside_geometries, 1, geometry_name}', '') as dump_site,
                to_char(loaded_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as load_time,
                to_char(tested_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as test_time,
                to_char(dumped_at at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as dump_time
            from combined_events
            left join users on users.id = user_id
            order by coalesce(dumped_at, tested_at, loaded_at) desc
        """
        , req.params.projectId
        , req.query.dateRange[0], req.query.dateRange[1]


    getBreaks: (req, res) ->
        getDriverDays(req)
        .then (driverDays) ->
            req.logs.messages.push "Driver days: #{JSON.stringify driverDays}"
            Promise.all R.map (driverDay) ->
                boundaryEvents = req.db.follower.jsonArrayQuery """
                    select type, (1000 * extract(epoch from created_at))::bigint as coord
                    from events
                    where user_id = $1 and project_id = $2 and type in ('entry', 'exit')
                        and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                        and geometry_id = (select id
                                           from geometries
                                           where overlay_id in (select id from overlays where project_id = $2
                                               and (properties->>'is_boundary')::boolean))
                    order by created_at
                """
                , driverDay.userId, req.params.projectId, driverDay.dayStartUtc, driverDay.dayEndUtc

                movementEvents = req.db.follower.jsonArrayQuery """
                    select type, (1000 * extract(epoch from created_at))::bigint as coord
                        , position
                        , (select coalesce(string_agg(geometries.properties->>'name', ', '
                                             order by geometries.properties->>'name'), '')
                           from geometries
                           join overlays on overlays.id = geometries.overlay_id
                           where overlays.deleted_at = '-infinity'
                               and ((overlays.properties->>'is_boundary') is null
                                    or (overlays.properties->>'is_boundary')::boolean = false
                               )
                               and geometries.deleted_at = '-infinity'
                               and ST_Contains(geometry,
                                       ST_SetSRID(ST_Point((position->>'lon')::double precision,
                                           (position->>'lat')::double precision), 4326))) as inside_geometries
                    from events
                    where user_id = $1 and project_id = $2 and type in ('move', 'stop')
                        and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                    order by created_at
                """
                , driverDay.userId, req.params.projectId, driverDay.signonAtUtc, driverDay.dayEndUtc

                beaconEvents = req.db.follower.jsonArrayQuery """
                    select first(type) as type, first(1000 * extract(epoch from created_at))::bigint as coord
                    from beacon_events
                    where role_id in (select id from beacon_roles where name = 'Break area')
                        and user_id = $1 and project_id = $2 and type in ('entry', 'exit')
                        and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                    group by beacon_id, type, created_at  -- deal with duplicate records
                    order by created_at, type
                """
                , driverDay.userId, req.params.projectId, driverDay.signonAtUtc, driverDay.dayEndUtc

                positions = req.db.follower.jsonArrayQuery """
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
                , driverDay.userId, req.params.projectId, driverDay.signonAtUtc, driverDay.dayEndUtc

                Promise.props
                    boundaryEvents: boundaryEvents
                    movementEvents: movementEvents
                    beaconEvents: beaconEvents
                    positions: positions
                .then (result) ->
                    activePeriodInterval =
                        start: coord: 1000 * driverDay.signonAtUtc
                        end: coord: 1000 * driverDay.dayEndUtc

                    MIN_BREAK = 3 * 60 * 1000 # ms

                    # Calculate stops from accelerometer data
                    stopSeries = Series.makeSeries [activePeriodInterval], result.movementEvents
                    #req.logs.messages.push "Stop series: #{JSON.stringify stopSeries}"
                    pointIntervals = Series.getPointIntervals stopSeries
                    #req.logs.messages.push "Point intervals: #{JSON.stringify pointIntervals}"
                    stopIntervals = R.filter (pInt) ->
                        pInt.end.type == "move" && Series.Interval.length(pInt) >= MIN_BREAK
                    , pointIntervals
                    #req.logs.messages.push "Stop intervals: #{JSON.stringify stopIntervals}"

                    scheduledBreakDetails =
                        shared.calcScheduledBreaks activePeriodInterval, result.beaconEvents, result.positions

                    markScheduled = (isScheduled) -> R.map R.assoc("isScheduled", isScheduled)

                    scheduledBreakIntervals = markScheduled(true) scheduledBreakDetails.breaks

                    req.logs.messages.push "Sched break intervals: #{JSON.stringify scheduledBreakIntervals}"

                    overlapsWith = R.curry (stopInterval, schedInt) ->
                        R.any(Series.Interval.contains(R.__, schedInt), [stopInterval.start, stopInterval.end]) ||
                            Series.Interval.contains(schedInt, stopInterval)

                    # Merge scheduled intervals with stop intervals, excluding overlaps (partial overlaps, as well as
                    # cases where the scheduled break is fully inside a regular break -
                    # in such situations scheduled break is preserved and the regular break is removed)
                    removeOverlaps = R.reject (stopInterval) ->
                        R.any overlapsWith(stopInterval), scheduledBreakIntervals

                    # Combine scheduled and unscheduled breaks into a single sequence
                    allStops = R.pipe(removeOverlaps, markScheduled(false), R.concat(scheduledBreakIntervals)
                        , R.sortBy((int) -> int.start.coord)) stopIntervals

                    res = R.merge driverDay, stops: allStops

                    R.merge res, if req.query.debug?.requests
                        _stopSeries: stopSeries
                        _beaconSeries: scheduledBreakDetails.beaconSeries
                        _scheduledBreakIntervals: scheduledBreakIntervals
                        _stopIntervals: stopIntervals
                        _beaconIntervals: scheduledBreakDetails.beaconIntervals
                        _boundaryEvents: result.boundaryEvents
                        _movementEvents: result.movementEvents
                        _beaconEvents: result.beaconEvents
                        _positions: result.positions
                    else
                        {}
            , R.filter(((driverDay) -> driverDay.signonAtUtc > 0), driverDays)


    getLoadCounts: (req, res) ->
        start = new Date

        geomFilter = (paramPlaceholder) ->
            """
                ST_Contains((select geometry from geometries where id = #{paramPlaceholder}),
                    ST_SetSRID(ST_Point((beacon_events.position->>'lon')::double precision
                    , (beacon_events.position->>'lat')::double precision), 4326))
                """

        processDriverDay = (driverDay) ->
            req.db.follower.jsonArrayQuery """
                select
                    (case when beacon_roles.name in ('Load area', 'Batch plant') then 'load' else 'dump' end) ||
                        '_' || beacon_events.type as type
                    , (1000 * extract(epoch from beacon_events.created_at))::bigint as coord
                    , beacon_events.name as name
                    , 'b' || beacon_id::text as area_id
                    , position
                    , beacon_roles.name as role_name
                    , false as is_geometry
                    , beacon_events.created_at
                    , beacon_events.id as event_id
                    , (
                        (beacon_roles.name in ('Load area', 'Batch plant')
                            and case when $5 = 0 then true else #{geomFilter("$5")} end)
                        or
                        (beacon_roles.name in ('Dump area', 'Paver')
                            and case when $6 = 0 then true else #{geomFilter("$6")} end)
                      ) as matches_user_filter
                from beacon_events
                join beacon_roles on role_id = beacon_roles.id
                where user_id = $1 and project_id = $2
                    and beacon_roles.name in ('Load area', 'Batch plant', 'Dump area', 'Paver')
                    and beacon_events.created_at >= to_timestamp($3) and beacon_events.created_at < to_timestamp($4)
                union all
                select 'dump_' || events.type as type
                    , (1000 * extract(epoch from events.created_at))::bigint as coord
                    , geometry_name as name
                    , 'g' || geometry_id::text as area_id
                    , events.position
                    , geometries.properties->>'purpose' as role_name
                    , true as is_geometry
                    , events.created_at
                    , events.id as event_id
                    , case when $6 = 0 then true else geometry_id = $6 end as matches_user_filter
                from events
                join geometries on geometry_id = geometries.id
                where user_id = $1 and project_id = $2
                    and events.type in ('entry', 'exit')
                    and geometries.properties->>'purpose' in ('fill', 'stockpile', 'waste')
                    and events.created_at >= to_timestamp($3) and events.created_at < to_timestamp($4)
                -- Sort by event ID to deal with entry-exit pairs in the same epoch
                order by area_id, created_at, event_id
            """
            , driverDay.userId, req.params.projectId, driverDay.dayStartUtc, driverDay.dayEndUtc
            , req.query.loadAreaId, req.query.dumpAreaId
            .then (proximityEvents) ->
                req.logs.messages.push "got proximity events, elapsed ms: #{(new Date) - start}"
                if R.isEmpty proximityEvents
                    {}
                else
                    movementEvents = req.db.follower.jsonArrayQuery """
                        select type, (1000 * extract(epoch from created_at))::bigint as coord
                        from events
                        where user_id = $1 and project_id = $2 and type in ('move', 'stop')
                            and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                        order by created_at
                    """
                    , driverDay.userId, req.params.projectId, driverDay.dayStartUtc, driverDay.dayEndUtc

                    driverDistances = req.db.follower.jsonArrayQuery """
                        select id, (1000 * extract(epoch from created_at))::bigint as coord,
                            coalesce (ST_Distance(
                                ST_SetSRID(ST_Point(positions.lon, positions.lat), 4326),
                                ST_SetSRID(ST_Point((lead(lon, 1) over (order by created_at))
                                                  , (lead(lat, 1) over (order by created_at))), 4326)::geography
                            ), 0) as distance
                        from positions
                        where user_id = $1 and project_id = $2
                            and created_at >= to_timestamp($3) and created_at < to_timestamp($4)
                        order by created_at
                    """
                    , driverDay.userId, req.params.projectId, driverDay.dayStartUtc, driverDay.dayEndUtc

                    Promise.props {movementEvents: movementEvents, driverDistances: driverDistances}
                    .then (reportData) ->
                        req.logs.messages.push "got movements & positions, elapsed ms: #{(new Date) - start}"
                        reportData = R.merge reportData, proximityEvents: proximityEvents
                        driverDayWithFlags = R.merge(driverDay, isSpecificDumpArea: parseInt(req.query.dumpAreaId) != 0)
                        queryParams = R.merge(req.query, customerId: req.customerId)
                        calcDayLoadCounts driverDayWithFlags, reportData, queryParams, req.logs

        getDriverDays(req)
        .then (driverDays) ->
            req.logs.messages.push "got driverDays, elapsed ms: #{(new Date) - start}"
            Promise.all R.map(processDriverDay, driverDays)
        .then (rows) ->
            req.logs.messages.push "calculated load counts, elapsed ms: #{(new Date) - start}"
            if req.query.debug?.requests
                rows
            else
                R.reject ((row) -> R.isEmpty(row) || R.isEmpty(row.cycles)), rows


    getDriverFitness: (req, res) ->
        req.db.follower.jsonArrayQuery """
            with permissions as (
                select user_id, array_to_json(array_agg(permission)) as permissions from permissions
                where project_id = $1 and deleted_at = '-infinity' and permission = 'extended_hours'
                group by user_id
            ), signons as (
                select signon_events.properties, signon_events.user_id, signon_events.created_at as timestamp,
                    to_char(signon_events.created_at at time zone
                        (select timezone from projects where id = $1), 'DD/MM/YY') as date,
                    to_char(signon_events.created_at at time zone
                        (select timezone from projects where id = $1), 'HH24:MI:SS') as time,
                    users.name as user_name,
                    coalesce(permissions.permissions, '[]'::json) as permissions
                from signon_events
                join users on users.id = user_id
                join user_roles on users.role_id = user_roles.id
                left join permissions on users.id = permissions.user_id
                where signon_events.project_id = $1
                    and (case when $2 = 0 then true else users.id = $2 end)
                    and (case when $3 = 0 then true else user_roles.id = $3 end)
                    and signon_events.created_at between (($4::timestamp without time zone) at time zone
                                                            (select timezone from projects where id = $1)) and
                                                         (($5::timestamp without time zone) at time zone
                                                            (select timezone from projects where id = $1)
                                                                + '1 day'::interval - '1 second'::interval)
                order by signon_events.created_at
            )
            select date, time, user_name, properties, permissions from signons
        """
        , req.params.projectId
        , req.query.userId
        , req.query.roleId
        , req.query.dateRange[0], req.query.dateRange[1]


module.exports = (helpers) ->
    getReports: helpers.withErrorHandling (req, res) ->
        Promise.resolve null
        .then ->
            reports = [
                { url: "projectVisits", label: "On-Site" }
                { url: "areas",         label: "Areas" }
                { url: "speedBands",    label: "Movement" }
                { url: "timeline",      label: "Activity" }
                { url: "driverFitness", label: "Driver fitness" }
            ]

            if req.permissions.cor
                reports.push { url: "breaks", label: "Chain of responsibility" }

            if req.permissions.loadCounts
                reports.push { url: "loadCounts", label: "Load counts" }

            if req.permissions.paving
                reports.push { url: "concreteTests", label: "Concrete tests" }

            sortedReports = R.sortBy R.prop('label'), reports

            permittedReports = R.filter (report) ->
                req.permissions.reports[report.url]
            , sortedReports
            
            res.json permittedReports


    getReport: helpers.withErrorHandling (req, res) ->
        #console.log "REPORT REQUEST START", moment().format "H:mm:ss"

        reportName = req.params.reportName

        if !req.permissions.reports[reportName]
            res.status(403).send "Report access denied"
            return

        reportHandlers =
            areas: "getAreas"
            breaks: "getBreaks"
            concreteTests: "getConcreteTests"
            driverFitness: "getDriverFitness"
            loadCounts: "getLoadCounts"
            projectVisits: "getProjectVisits"
            speedBands: "getSpeedBands"
            timeline: "getTimeline"

        reportHandler = handlers[reportHandlers[reportName]]

        if !reportHandler?
            res.status(404).send "Report not found"
            return

        reportHandler(req, res)
        .then (result) ->
            #console.log "REPORT REQUEST END", moment().format "H:mm:ss"
            res.json result


    _calcDayLoadCounts: calcDayLoadCounts
    _normaliseDumpIntervals: normaliseDumpIntervals
    _equalBy: equalBy
    _reduceToSingleDump: reduceToSingleDump
    _adjustIntervalsToOverlapMidpoints: adjustIntervalsToOverlapMidpoints
    _recombineAperturePairs: recombineAperturePairs

