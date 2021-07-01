getDriverDays = require "./driver_days"

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
    R.pipe(R.dropWhile(R.pathEq(["start", "type"], "dump_entry"))      # Drop initial dumps - no sense without a load
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


geomFilter = (paramPlaceholder) ->
    """
    ST_Contains((select geometry from geometries where id = #{paramPlaceholder}),
        ST_SetSRID(ST_Point((beacon_events.position->>'lon')::double precision
        , (beacon_events.position->>'lat')::double precision), 4326))
    """


processDriverDay = R.curry (req, start, driverDay) ->
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
        where events.user_id = $1 and events.project_id = $2
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


getReportData = (req) ->
    start = new Date

    getDriverDays(req)
    .then (driverDays) ->
        req.logs.messages.push "got driverDays, elapsed ms: #{(new Date) - start}"
        Promise.all R.map(processDriverDay(req, start), driverDays)
    .then (rows) ->
        req.logs.messages.push "calculated load counts, elapsed ms: #{(new Date) - start}"
        if req.query.debug?.requests
            rows
        else
            R.reject ((row) -> R.isEmpty(row) || R.isEmpty(row.cycles)), rows

getReportData._helpers =
    calcDayLoadCounts: calcDayLoadCounts
    normaliseDumpIntervals: normaliseDumpIntervals
    equalBy: equalBy
    reduceToSingleDump: reduceToSingleDump
    adjustIntervalsToOverlapMidpoints: adjustIntervalsToOverlapMidpoints
    recombineAperturePairs: recombineAperturePairs

module.exports = getReportData