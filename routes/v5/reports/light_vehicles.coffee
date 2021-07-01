# Take |-exit, entry-exit & entry-| intervals
takeVisitIntervals =
    R.filter (interval) -> interval.start.type == "entry" || interval.end.type == "exit"


# Vehicle -> Promise (Int | Undefined)
calcVehicleDistance = (req, vehicle) ->
    req.db.follower.jsonArrayQuery """
        select type, user_id, extract(epoch from created_at)::int as coord
        from beacon_events
        where beacon_id = $1
            and created_at between to_timestamp($2) and to_timestamp($3)
        order by user_id, created_at
    """
    , vehicle.beaconId, vehicle.startTimeUtc, vehicle.endTimeUtc
    .then (beaconEvents) ->
        dayInterval =
            start: coord: vehicle.startTimeUtc
            end: coord: vehicle.endTimeUtc

        prepIntervalsPerUser = R.pipe(
              Series.makeSeries([dayInterval])
            , Series.getPointIntervals
            , takeVisitIntervals
        )

        userIntervals = R.pipe(
              R.groupBy((event) -> event.userId.toString())
            , R.values
            , R.map(prepIntervalsPerUser)
            , R.flatten
            , R.sortBy(R.path ["start", "coord"])
            , Series.calcMinimalCoveringIntervals
        ) beaconEvents

        Promise.all R.map (userInterval) ->
            req.db.follower.jsonQuery """
                with distances as (
                    select coalesce (ST_Distance(
                        ST_SetSRID(ST_Point(positions.lon, positions.lat), 4326),
                        ST_SetSRID(ST_Point((lead(lon, 1) over (order by created_at))
                                          , (lead(lat, 1) over (order by created_at))), 4326)::geography
                        ), 0) as distance
                    from positions
                    where project_id = $1 and user_id = $2
                        and created_at between to_timestamp($3) and to_timestamp($4)
                )
                select sum(distance)::int as distance from distances
            """
            , req.params.projectId, userInterval.end.userId, userInterval.start.coord, userInterval.end.coord
        , userIntervals
        .then (distances) ->
            distance: R.sum R.pluck "distance", distances
            _beaconEvents: beaconEvents
            _userIntervals: userIntervals
            _distances: distances


getVehicleSignons = (req, vehicle) ->
    req.db.follower.jsonArrayQuery """
        select signon_events.properties, signon_events.user_id
            , to_char(signon_events.created_at at time zone
                (select timezone from projects where id = $1), 'HH24:MI') as time
            , users.name as user_name
            , (case user_roles.name when '' then description else user_roles.name end) as user_role
        from signon_events
        join users on users.id = user_id
        join user_roles on users.role_id = user_roles.id
        where signon_events.project_id = $1 and signon_events.vehicle_id = $2
            and signon_events.created_at between to_timestamp($3) and to_timestamp($4)
        order by signon_events.created_at
    """
    , req.params.projectId, vehicle.id, vehicle.startTimeUtc, vehicle.endTimeUtc


module.exports = (req) ->
    req.db.follower.jsonArrayQuery """
        with vars as (
            select *, start_tstamp at time zone timezone as start_time
                , least(clock_timestamp(),
                    (start_tstamp + '23:59:59'::interval) at time zone timezone) as end_time
            from (
                select ($4::timestamp without time zone) as start_tstamp
                    , (select timezone from projects where id = $1) as timezone
                    , (select customer_id from projects where id = $1) as customer_id
                    , $2::bigint as vehicle_id, $3::bigint as role_id
            ) a
        )
        select vehicles.id, number, make, model, beacon_id
            , to_char((select start_time from vars) at time zone (select timezone from vars), 'DD/MM/YY') as date
            , extract(epoch from (select start_time from vars))::int as start_time_utc
            , extract(epoch from (select end_time from vars))::int as end_time_utc
            , vehicle_roles.name as vehicle_type
        from vehicles
        join vehicle_roles on vehicles.role_id = vehicle_roles.id
        where customer_id = (select customer_id from vars)
            and beacon_id is not null
            and (case when (select vehicle_id from vars) = 0 then true else vehicles.id = (select vehicle_id from vars) end)
            and (case when (select role_id from vars) = 0 then true else role_id = (select role_id from vars) end)
        order by start_time_utc, number
    """
    , req.params.projectId, req.query.vehicleId, req.query.roleId, req.query.dateRange[0]
    .then (vehicles) ->
        Promise.all R.map (vehicle) ->
            Promise.props
                travelDistance: calcVehicleDistance(req, vehicle)
                signons: getVehicleSignons(req, vehicle)
            .then (vehicleDetails) ->
                if req.query.debug?.requests
                    R.merge vehicle, vehicleDetails
                else
                    if vehicleDetails.travelDistance.distance < 0.01 && R.isEmpty(vehicleDetails.signons)
                        undefined
                    else
                        R.merge (R.omit ["beaconId", "startTimeUtc", "endTimeUtc"], vehicle)
                            , {travelDistance: vehicleDetails.travelDistance, signons: vehicleDetails.signons}
        , vehicles
    .then (vehicles) ->
        R.reject R.isNil, vehicles
