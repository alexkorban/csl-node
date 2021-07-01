shared = require "../shared"
getDriverDays = require "./driver_days"

module.exports = (req) ->
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

                dataWithStops = R.merge driverDay, stops: allStops

                R.merge dataWithStops, if req.query.debug?.requests
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
