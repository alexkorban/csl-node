httpClient = require if process.env.NODE_ENV == "dev" then "http" else "https"
crypto = require "crypto"
uid = require "uid-safe"
aws = require "aws-sdk"

queryUserApproval = (req) ->
    req.db.master.jsonQuery """
        select coalesce((select customer_id from projects where id = $1) =
            (select customer_id from projects where id = (select project_id from users_projects where user_id = $2 limit 1)), false)
        as approved
    """
    , req.params.projectId, req.params.id

class SyncHandlers
    constructor: (@db, @params, @data, @logs) ->
        @userCid = @params.userId
        @projectCid = @params.projectId

        @logs.userCid = @userCid
        @logs.projectCid = @projectCid

        @fullSetRequired = {}
        @hashes = @params.hashes


    addExtraResponseData: (responseData) =>
        # these are things that change independently from user actions, so we look for updates on every sync
        extraQueries =
            baseLayers: @getUpdatedBaseLayers()
            downloadBoundaries: @getUpdatedDownloadBoundaries()
            overlays: @getUpdatedOverlays()
            permissions: @getUpdatedPermissions()
            positions: @getUpdatedPositions()
            weather: @getWeather()
            vehicles: @getUpdatedVehicles()
            beacons: @getUpdatedBeacons()
            beaconRoles: @getUpdatedBeaconRoles()

        Promise.props extraQueries
        .then (extraResponseData) =>
            R.merge responseData, (R.merge extraResponseData, projectId: @projectCid)


    handleRequest: (requestType, result) =>
        dataItem = R.find R.propEq("type", requestType), @data
        items = dataItem?.items
        return Promise.resolve result if !items? || R.isEmpty items
        @logs.messages.push "Handling #{requestType}"
        @[requestType](items)
        .then (res) =>
            return result if !res?
            R.merge result, res


    getIdsFromCids: =>
        @db.jsonQuery """
            select (select id from users where cid = $1) as user_id, (select id from projects where cid = $2) as project_id
        """, @userCid, @projectCid
        .then (result) =>
            {@userId, @projectId} = result


    # incoming request handler for device queue items
    createUser: (items) =>
        latest = R.last items
        @db.query """
            with role as (select id from user_roles where lower(name) = lower($4))
            insert into users (name, phone_no, company, truck_no, truck_wheel_count, cid, email, role_id, description)
            values ($1, $2, $3, $5, $6, $7, $8,
                -- role_id
                case when exists(select * from role) then (select first(id) from role) else (select id from user_roles where name='') end,
                -- description (either the role string or empty if we found a matching role_id)
                case when exists(select * from role) then '' else $4 end
            ) returning id, cid
        """
        , latest.name, latest.phoneNo, latest.company, latest.role, latest.truckNo, (latest.truckWheelCount || 0)
        , db.generateCid(), latest.email
        .then (user) =>
            @logs.messages.push "User created #{JSON.stringify user.rows[0]}"
            @userId = user.rows[0].id
            @userCid = user.rows[0].cid
            @logs.userCid = @userCid

            if S(latest.name).startsWith "DemoZHJ1io"  # Give permissions to the demo account immediately
                @db.query """
                    insert into permissions (user_id, project_id, permission) values
                        ($1, 2, 'view_overlays'), ($1, 2, 'use_diagnostics'),
                        ($1, 3, 'view_overlays'), ($1, 3, 'use_diagnostics')
                """, @userId
                .then =>
                    user: id: @userCid
            else
                user: id: @userCid


    # incoming request handler for device queue items
    updateUser: (items) =>
        # apply the latest update only
        latest = R.last items

        @db.query """
            with role as (select id from user_roles where lower(name) = lower($4))
            update users set name = $1, phone_no = $2, company = $3, truck_no = $5, truck_wheel_count = $6,
                role_id = (case when exists(select * from role) then (select first(id) from role) else (select id from user_roles where name='') end),
                description = (case when exists(select * from role) then '' else $4 end),
                updated_at = clock_timestamp(), email = $8
            where id = $7
        """
        , latest.name, latest.phoneNo, latest.company, latest.role, latest.truckNo, latest.truckWheelCount, @userId, latest.email
        .then =>
            user: R.merge latest, id: @userCid


    recordInfoEvent: (type, events) =>
        @db.query """
            insert into info_events(user_id, project_id, type, properties, created_at)
            select $1::bigint,
                (select id from projects where cid = (items->>'project_id')::text),
                $2, (items->>'properties')::json, (items->>'created_at')::timestamp
            from json_array_elements($3) as items
        """
        , @userId, type, JSON.stringify db.renameKeysForDb events
        .then => null



    recordUpload: (events) =>
        @recordInfoEvent 'upload', events


    recordAppStart: (events) =>
        @recordInfoEvent 'app_start', events


    recordAppStop: (events) =>
        @recordInfoEvent 'app_stop', events


    recordError: (events) =>
        @recordInfoEvent 'error', events

    recordDiagnostics: (events) =>
        @recordInfoEvent 'diagnostics', events


    recordCred: (creds) =>
        # get an array of cred hashes which the user doesn't yet have
        @db.jsonArrayQuery """
            select permission, cred_hash from project_creds
            where project_id = $2
                and permission not in (select permission from permissions where user_id = $1 and project_id = $2 and deleted_at = '-infinity')
        """, @userId, @projectId
        .then (projectCreds) =>
            # see if the submitted creds match any of the available project creds
            addPermissionIfMatchesHash = R.curry (cred, projectCred) =>
                bcrypt.compareAsync(cred.value, projectCred.credHash)
                .then (doesMatch) =>
                    return if !doesMatch
                    @db.query """
                        insert into permissions (user_id, project_id, permission) values ($1, $2, $3)
                    """
                    , @userId, @projectId, projectCred.permission

            maybeAddCred = (cred) =>
                Promise.all R.map (addPermissionIfMatchesHash cred), projectCreds

            Promise.all R.map maybeAddCred, creds
        .then => null


    requestFullSet: (items) =>
        latest = R.last items
        @logs.messages.push "Full set flags: #{JSON.stringify latest}"
        @fullSetRequired = latest

        Promise.resolve null


    # Incoming request handler for device queue items
    # requires data.length > 0
    recordPosition: (data) =>
        # Only positions which are within the boundary of an active project are inserted;
        # nothing will be inserted if the positions are outside any project boundary

        # json_populate_recordset can't handle any kind of nesting at present, so
        # the accel property has to be converted into a string
        positions = R.map ((pos) -> pos.accel = JSON.stringify pos.accel; pos), db.renameKeysForDb data

        @latestPosition = R.last positions

        @db.query """
            insert into positions(user_id, project_id, lon, lat, accuracy, speed, heading, created_at, altitude,
                altitude_accuracy, accel)
                select $1 as user_id, project_id, points.*
                from (select lon, lat, accuracy, round(speed::numeric, 2)::real, round(heading::numeric, 2)::real,
                          created_at, coalesce(altitude, 0), coalesce(altitude_accuracy, 0),
                          coalesce(accel, '{"x": 0, "y": 0, "z": 0}'::json)
                      from json_populate_recordset(null::positions, ($2)::json)
                ) as points
                    join geometries on ST_Contains(geometry, ST_SetSRID(ST_Point(points.lon, points.lat), 4326))
                    join overlays on overlay_id = overlays.id
                    join projects on project_id = projects.id
                where (overlays.properties->>'is_boundary')::bool and projects.deleted_at = '-infinity'
        """
        , @userId, JSON.stringify positions
        .then => null


    # Incoming request handler for device queue items;
    # all events must contain enough information to establish their provenance
    # (i.e. project); this can be a geometry_id, overlay_id or a lon/lat.
    # I don't want to rely on the timestamp (e.g. matching to position by time)
    # as there's no guarantee that the time on a user's device is correct
    recordEvent: (data) =>
        # json_populate_recordset can't handle any kind of nesting at present, so
        # properties have to be converted into a string

        events = R.map ((item) ->
            item.properties = JSON.stringify item.properties
            item.position = if item.position? then JSON.stringify item.position else null
            item), (db.renameKeysForDb data)

        scanData = R.filter R.propEq("type", "concrete_movement"), data

        noDuplicatesScanData = R.uniqBy (item) ->
            step: item.properties.step
            id: item.properties.docketId
        , scanData

        scanEvents = R.map ((item) ->
            item.properties = JSON.stringify item.properties
            item.position = if item.position? then JSON.stringify item.position else null
            item), (db.renameKeysForDb noDuplicatesScanData)



        entryExitEvents = =>
            q = """
                insert into events(user_id, project_id, type, geometry_id, geometry_name, created_at, position)
                    with event_records as (
                        select type, geometry_id, geometry_name, created_at, position::json
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, project_id,
                        event_records.type, event_records.geometry_id, event_records.geometry_name, event_records.created_at,
                        case
                            when event_records.position is null then null
                            when exists (select id from projects where id = project_id
                                and ST_Contains(download_boundary,
                                        ST_SetSRID(ST_Point((event_records.position->>'lon')::double precision,
                                                            (event_records.position->>'lat')::double precision), 4326)))
                            then event_records.position
                        else null end as position
                    from event_records
                        join geometries on event_records.geometry_id::bigint = geometries.id
                        join overlays on overlay_id = overlays.id
                        join projects on project_id = projects.id
                    where projects.deleted_at = '-infinity'
                        and (event_records.type = 'entry' or event_records.type = 'exit')
                        and exists (select 1 from users where id = $2)
            """
            @db.query q, (JSON.stringify events), @userId

        jhaEvents = =>
            q = """
                insert into events(user_id, project_id, type, position, properties, created_at)
                    with event_records as (
                        select type, position::json, properties::json, created_at
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, project_id, event_records.*
                    from event_records
                        join geometries on
                            (event_records.properties->'inside_geometries'->0->>'geometry_id')::bigint = geometries.id
                        join overlays on overlay_id = overlays.id
                        join projects on project_id = projects.id
                    where projects.deleted_at = '-infinity'
                        and event_records.type = 'jha'
                        and exists (select 1 from users where id = $2)
            """

            @db.query q, (JSON.stringify events), @userId

        concreteMovementEvents = =>
            @db.query """
                insert into events(user_id, project_id, type, position, properties, created_at)
                    with event_records as (
                        select type, position::json, properties::json, created_at
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, $3 as project_id, event_records.*
                    from event_records
                        join projects on projects.id = $3
                    where projects.deleted_at = '-infinity'
                        and event_records.type = 'concrete_movement'
                        and exists (select 1 from users where id = $2)
                        and not exists (select 1 from events
                                        where type = 'concrete_movement'
                                            and properties->>'docket_id' = event_records.properties->>'docket_id'
                                            and properties->>'step' = event_records.properties->>'step')
            """
            , (JSON.stringify scanEvents), @userId, @projectId

        signonEvents = =>
            @db.query """
                insert into signon_events(user_id, project_id, position, properties, created_at)
                    with event_records as (
                        select type, position::json, properties::json, created_at
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, $3 as project_id, event_records.position, event_records.properties
                        , event_records.created_at
                    from event_records
                        join projects on projects.id = $3
                    where projects.deleted_at = '-infinity'
                        and event_records.type = 'signon'
                        and exists (select 1 from users where id = $2)
            """
            , (JSON.stringify events), @userId, @projectId


        motionEvents = =>
            @db.query """
                insert into events(user_id, project_id, type, properties, created_at, position)
                    with event_records as (
                        select type, position::json, properties::json, created_at
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, $3 as project_id
                        , event_records.type, event_records.properties, event_records.created_at
                        , case
                            when event_records.position is null then null
                            when exists (select id from geometries
                                         where overlay_id =
                                                (select id from overlays
                                                 where (properties->>'is_boundary')::boolean and project_id = $3)
                                            and ST_Contains(geometry,
                                                ST_SetSRID(ST_Point((event_records.position->>'lon')::double precision,
                                                                    (event_records.position->>'lat')::double precision), 4326))
                                        )
                                then event_records.position
                            else null end as position
                    from event_records
                        join projects on projects.id = $3
                    where projects.deleted_at = '-infinity'
                        and (event_records.type = 'move' or event_records.type = 'stop')
                        and exists (select 1 from users where id = $2)
            """
            , (JSON.stringify events), @userId, @projectId


        prestartChecklistEvent = =>
            @db.query """
                insert into events(user_id, project_id, type, position, properties, created_at)
                    with event_records as (
                        select type, position::json, properties::json, created_at
                        from json_populate_recordset(null::events, $1)
                    )
                    select $2 as user_id, $3 as project_id, event_records.*
                    from event_records
                        join projects on projects.id = $3
                    where projects.deleted_at = '-infinity'
                        and event_records.type = 'prestart_checklist'
                        and exists (select 1 from users where id = $2)
            """
            , (JSON.stringify events), @userId, @projectId


        Promise.all [entryExitEvents(), jhaEvents(), concreteMovementEvents(), signonEvents(), motionEvents(),
            prestartChecklistEvent()]
        .then (results) ->
            return null if process.env.NODE_ENV == "production"  # No Reactor in production!

            # ping the Reactor via HTTP(S)
            reactorParams = switch process.env.NODE_ENV
                when "production" then host: "csl-safesitereactor.herokuapp.com"
                when "staging" then host: "csl-safesitereactor-staging.herokuapp.com"
                else host: "localhost:6000"

            reactorParams.path = "/6BC25A71-4281-4DD8-955D-25ABCE620D7E"

            httpReq = httpClient.get reactorParams, (res) =>
                console.log "Notified Reactor of new events, status: #{res.statusCode}"

            httpReq.on "error", (e) =>
                console.log "Failed to notify Reactor: #{e.message}"

            null


    recordBeaconEvent: (data) =>
        events = R.map ((item) ->
            item.properties = JSON.stringify item.properties
            item.position = if item.position? then JSON.stringify item.position else null
            item), (db.renameKeysForDb data)

        @db.query """
            insert into beacon_events(user_id, project_id, type, beacon_id, created_at, properties, position
                , role_id, name, description)
                with event_records as (
                    select type, created_at, beacon_id, properties, position::json
                    from json_populate_recordset(null::beacon_events, $1)
                )
                select $2 as user_id, project_id,
                    event_records.type, event_records.beacon_id, event_records.created_at, event_records.properties
                    , case
                        when event_records.position is null then null
                        when exists (select id from projects where id = project_id
                            and ST_Contains(download_boundary,
                                    ST_SetSRID(ST_Point((event_records.position->>'lon')::double precision,
                                                        (event_records.position->>'lat')::double precision), 4326)))
                        then event_records.position
                      else null end as position
                    , beacons.role_id, beacons.name, beacons.description
                from event_records
                    join beacons on event_records.beacon_id::bigint = beacons.id
                    join projects on project_id = projects.id
                where projects.deleted_at = '-infinity'
                    and (event_records.type = 'entry' or event_records.type = 'exit')
                    and event_records.created_at is not null
                    and exists (select 1 from users where id = $2)
        """
        , (JSON.stringify events), @userId
        .then (result) -> null


    recordObservation: (observations) =>
        setMarkerProps = (observation) =>
            markerProps = icon: "exclamation", prefix: "fa", markerColor: "orange", iconColor: "white"
            R.merge observation, properties: R.merge(observation.properties, markerProps)
        observations = R.map setMarkerProps, observations

        @db.query """
            insert into geometries(overlay_id, created_at, properties, geometry)
                select (select id from overlays where name = 'User defined areas' and project_id = projects.id) as overlay_id,
                    (items->>'created_at')::timestamp, (items->>'properties')::json,
                    ST_SetSRID(ST_Point((items->>'lon')::double precision, (items->>'lat')::double precision), 4326) as geometry
                from json_array_elements($1) as items
                    join geometries
                        on ST_Contains(geometries.geometry, ST_SetSRID(ST_Point((items->>'lon')::double precision, (items->>'lat')::double precision), 4326))
                    join overlays on overlay_id = overlays.id
                    join projects on project_id = projects.id
                where (overlays.properties->>'is_boundary')::bool and projects.deleted_at = '-infinity'
        """
        , JSON.stringify db.renameKeysForDb observations
        .then => null


    recordVehicle: (vehicles) =>
        makeVehiclePromises = (vehicle) =>
            updatePromise = @db.query """
                update vehicles
                set rego_exp_date = $1, mileage = $2, updated_at = $3
                where number = $4
            """
            , vehicle.regoExpDate, vehicle.mileage, vehicle.createdAt, vehicle.number

            insertPromise =
                if !@projectId?
                    Promise.resolve null
                else
                    @db.query """
                        insert into vehicles (cid, number, mileage, rego, rego_exp_date, make, model, created_at, customer_id)
                        with vehicle_data as (
                            select number, mileage, rego, rego_exp_date, make, model, created_at
                            from json_populate_record(null::vehicles, $2)
                        )
                        select $3, vehicle_data.*, (select customer_id from projects where id = $1) as customer_id
                        from vehicle_data
                        where not exists (select 1 from vehicles where number = vehicle_data.number)
                    """
                    , @projectId, JSON.stringify db.renameKeysForDb vehicle
                    , db.generateCid()

            Promise.all [updatePromise, insertPromise]

        Promise.all R.map makeVehiclePromises, vehicles
        .then => null


    recordBeacon: (beacons) =>
        dbRequest = (beacon) =>
            # If the beacon already exists in the DB, it will be updated;
            # if it doesn't exist, it will be created
            @db.query """
                update beacons
                set project_id = $1, role_id = $2, name = $3, description = $4, updated_at = clock_timestamp()
                where beacon_uuid = $5 and major = $6 and minor = $7
                    and customer_id = (select customer_id from projects where id = $1)
            """
            , @projectId, beacon.roleId, beacon.name, beacon.description, beacon.beaconUuid, beacon.major, beacon.minor
            .then =>
                @db.query """
                    insert into beacons (project_id, customer_id, beacon_uuid, major, minor, role_id, name
                        , description, cid)
                    select $1, (select customer_id from projects where id = $1), $2, $3, $4, $5, $6, $7, $8
                    where not exists (select 1 from beacons
                                      where beacon_uuid = $2 and major = $3 and minor = $4)
                """
                , @projectId, beacon.beaconUuid, beacon.major, beacon.minor, beacon.roleId
                , beacon.name, beacon.description, db.generateCid()
            .then => null
        Promise.all R.map dbRequest, beacons


    getLastSyncTime: =>
        @logs.messages.push "Getting last sync time"
        @db.jsonQuery """
            select (select synced_at from users_projects where user_id = $1 and project_id = $2) as project_synced_at,
                (select max(synced_at) from users_projects where user_id = $1) as user_synced_at
        """
        , @userId, @projectId
        .then (row) =>
#            if !row.updateUserSyncedAt?  # e.g. invalid user ID
#                throw new Error "Sync record for user #{@userId}/project #{@projectId} not found"
            @projectSyncedAt = row.projectSyncedAt || '-infinity'
            @userSyncedAt = row.userSyncedAt || '-infinity'
            @logs.messages.push "Last sync: #{@userSyncedAt}; this project: #{@projectSyncedAt}"
            null


    updateUserProject: =>
        # users.project_id reflects the project they are currently in;
        # @projectId reflects their assigned project (via download boundary lookup)
        if !@latestPosition?
            return Promise.resolve null

        @logs.messages.push "Updating user's project"
        @db.query """
            update users
            set project_id = (select project_id from overlays
                                join geometries on overlay_id = overlays.id
                                join projects on project_id = projects.id
                                where (overlays.properties->>'is_boundary')::bool and projects.deleted_at = '-infinity'
                                    and ST_Contains(geometry, ST_SetSRID(ST_Point($1, $2), 4326)))
            where id = $3
        """
        , @latestPosition.lon, @latestPosition.lat, @userId
        .then => null


    updateUserSyncedAt: =>
        if !@projectId?
            return Promise.resolve null

        @logs.messages.push "Updating sync time"
        q = if @projectSyncedAt == '-infinity'
            "insert into users_projects (user_id, project_id, synced_at) values ($1, $2, clock_timestamp())"
        else
            "update users_projects set synced_at = clock_timestamp() where user_id = $1 and project_id = $2"

        @db.query q
        , @userId, @projectId
        .then => null


    getProjectId: =>
        @logs.messages.push "Getting the current project ID for the user"
        if @projectId?
            @logs.messages.push "Project ID #{@projectId} known by the client"
            return Promise.resolve null
        if !@latestPosition?
            @logs.messages.push "No position available, project ID unknown"
            return Promise.resolve null

        @db.jsonQuery """
            select id, cid
            from projects
            where deleted_at = '-infinity' and ST_Contains(download_boundary, ST_SetSRID(ST_Point($1, $2), 4326))
        """
        , @latestPosition.lon, @latestPosition.lat
        .then (project) =>
            if !project?
                @logs.messages.push "Position outside boundaries, project ID unknown"
            # Project can be null if the user is outside any download boundary
            @projectId = project?.id ? null
            @projectCid = project?.cid ? null


    # Get the set of the most recent positions for every other user currently in the project
    # user_id is used as id because we're tracking *users* so there's at most one position per user
    getUpdatedPositions: =>
        @logs.messages.push "Getting positions of other users"

        #### TEST CODE: generates fake user positions and trails
        #### This math staff is used: http://mathworld.wolfram.com/Rose.html

        if @projectId == 3  # Test code to evaluate data usage
            secondOfTheDay = () ->
                d = new Date()
                (d - (new Date(d)).setHours(0,0,0,0)) / 100000.0

            return @db.jsonArrayQuery """
                with coords as (
                    select row_number() over() as index
                         , ST_Y(ST_Centroid(ST_Envelope(geometry))) as lat
                         , ST_X(ST_Centroid(ST_Envelope(geometry))) as lon
                    from overlays
                        join geometries on overlays.id = geometries.overlay_id
                    where project_id = $1 and overlays.deleted_at = '-infinity'
                ),
                coef as (
                    select array[0.5, 0.33, 0.66, 0.25, 0.2, 1.0, 2.0, 3.0, 4.0, 5.0] as n
                ),
                guys as (
                    select row_number() over() as index
                     , users.name as name
                     , company
                     , users.id as user_id
                     , coalesce(nullif(user_roles.name,''), description) as role
                     , to_char((now() - trunc(random() * 9) * '1 minute'::interval) at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as last_position_at
                     , created_at as created_at
                     , truck_no
                    from users join user_roles on users.role_id = user_roles.id
                    where project_id = $1
                )
                select c.lat + $3 * cos((select n[(g.user_id % 10 + 1)] from coef) * $2) * cos($2) as lat
                     , c.lon + $3 * cos((select n[(g.user_id % 10 + 1)] from coef) * $2) * sin($2) as lon
                     , trunc(cast(2 * random() as numeric), 2) as speed
                     , trunc(random() * 359 + 1) as heading
                     , g.name as user_name
                     , g.company
                     , g.truck_no
                     , g.user_id::text
                     , g.role
                     , case when g.user_id % 2 = 0 then trunc(random() * 1000000 + 1)::text else '' end as phone_no
                     , g.last_position_at
                     , g.last_position_at as created_at
                     ,(select json_agg(r)
                       from (select c.lat + $3 * cos((select n[(g.user_id % 10 + 1)] from coef) * ($2 - index/10.0)) * cos(($2 - index/10.0)) as lat
                                  , c.lon + $3 * cos((select n[(g.user_id % 10 + 1)] from coef) * ($2 - index/10.0)) * sin(($2 - index/10.0)) as lon
                                  , 10 as speed
                                  , trunc(random() * 359 + 1) as heading
                                  , to_char((g.created_at - index * '1 minute'::interval) at time zone (select timezone from projects where id = $1), 'DD/MM/YY HH24:MI:SS') as created_at
                                  , s.index + 1 as index
                             from generate_series(1, $4) as s(index)) r
                      ) as trail
                from guys g
                    join coords as c on c.index = g.index
            """
            , @projectId
            , secondOfTheDay()    # Theta (polar coordinates' angle)
            , 0.01                # Amplitude (how wide the wandering is)
            , 15                  # Trail length (set high to reveal the trajectories)
            .then (result) ->
                fullSet: true
                added: result
                deleted: []

        ####

        # There are never any deleted positions because the client handles the case of
        # users who left the project by displaying the last position with a timeout
        @db.jsonArrayQuery """
            with recent_positions as (
                select *, row_number() over(partition by user_id order by created_at desc) as index
                from positions
                where project_id = $2 and user_id != $1 and created_at >= now() - interval '20 minutes'
            )
            select lon, lat, speed, heading,
                to_char(rp.created_at at time zone (select timezone from projects where id = $2), 'DD/MM/YY HH24:MI:SS') as created_at,
                cid as id, cid as user_id, users.name as user_name, phone_no, company, coalesce(nullif(user_roles.name,''), description) as role, truck_no, truck_wheel_count,

                case when user_roles.name = 'Concrete truck' then
                (
                    with status as (
                        select last(beacon_roles.name order by beacon_events.created_at) = 'Batch plant' as is_loaded
                        from beacon_events
                        join beacon_roles on beacon_events.role_id = beacon_roles.id
                        where ((type = 'exit' and beacon_roles.name = 'Batch plant') or (type = 'entry' and beacon_roles.name = 'Paver'))
                        and beacon_events.project_id = $2
                        and beacon_events.user_id = rp.user_id
                        and beacon_events.created_at at time zone (select timezone from projects where id = $2)
                                                     >= date_trunc('day', clock_timestamp() at time zone (select timezone from projects where id = $2))
                    ) select coalesce(is_loaded, false) from status
                )
                else false
                end as is_loaded,

                case when (user_roles.properties->>'is_machine')::boolean then
                    (select coalesce(json_agg(r), '[]') from (select lon, lat, speed, heading, index,
                        to_char(created_at at time zone (select timezone from projects where id = $2), 'DD/MM/YY HH24:MI:SS') as created_at
                     from recent_positions
                     where recent_positions.user_id = rp.user_id and index > 1
                        and recent_positions.created_at >= now() - interval '5 minutes' order by index) r
                    )::json
                    else '[]'::json
                end as trail
            from recent_positions rp, users join user_roles on users.role_id = user_roles.id
            where index = 1 and users.id = rp.user_id
            order by user_id
        """
        , @userId, @projectId
        .then (result) ->
            fullSet: true
            added: result
            deleted: []


    getWeather: =>
        @logs.messages.push "Getting weather report for the project."
        @db.jsonQuery """
            with project as
                (select download_boundary, properties from projects where id = $1)
            , latest_weather as
                (select * from weather where created_at >= now() - '2 hours'::interval)
            , final as
                (select created_at, air_temp, wind_dir, wind_speed, rain_trace, pressure, (pressure - (lag(pressure) over(partition by name order by created_at))) as press_tend, properties
                from latest_weather
                cross join project
                where ST_DWithin(project.download_boundary::geography, ST_SetSRID(ST_MakePoint(latest_weather.lon, latest_weather.lat), 4326)::geography, 25000)
                )
            select * from final order by final.created_at desc limit 1
        """
        , @projectId


    # Returns a timestamp based diff or a full set, depending on args
    # Params:
    # queryAdded - Timestamp -> Promise SqlResult
    # queryDeleted - Timestamp -> Promise SqlResult
    # queryHash - () -> Promise SqlResult
    # fullSetRequired - Bool
    # clientHash - String
    # syncedAt - Timestamp
    getCollection: (params) =>
        syncedAt = if params.fullSetRequired then '-infinity' else params.syncedAt  # note that syncedAt can also be -infinity
        returningFullSet = syncedAt == '-infinity'

        added = params.queryAdded syncedAt

        deleted = if returningFullSet
            Promise.resolve []  # There's no need to find deleted items when returning a full set of current data to the client
        else
            params.queryDeleted(syncedAt).then R.map R.prop("id")

        hash = if returningFullSet
            Promise.resolve ""  # The hash isn't checked when returning a full set (there's no need)
        else
            params.queryHash()
            .then (result) =>
                crypto.createHash("sha1").update(JSON.stringify R.sortBy R.prop("id"), result).digest("hex")

            # This is how you would calculate the hash in Postgres:
            # select encode(digest(json_agg(p)::text, 'sha1'), 'hex') from
            #     (select permission as id, to_char(updated_at, 'YYYY-MM-DD HH24:MI:SSZ') as updated_at from permissions) p
            # But we don't do that because different collections require different queries to get the JSON string to hash

        Promise.props added: added, deleted: deleted, hash: hash
        .then (result) =>
            if R.isEmpty(result.added) && R.isEmpty(result.deleted) && !returningFullSet && result.hash != params.clientHash
                # Out of sync: the diff for the given sync time is empty, but the client & server hashes are different 
                # => return a full set to bring the client back in sync
                @getCollection R.merge params, fullSetRequired: true
            else
                fullSet: returningFullSet
                added: result.added
                deleted: result.deleted


    # Data level: customer
    # Return boundaries as GeoJSON features because they are passed to Turf on the client
    getUpdatedDownloadBoundaries: =>
        @logs.messages.push "Getting download boundaries"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select 'Feature' as type, cid as id, '{}'::json as properties,
                    to_char(updated_at at time zone (projects.timezone), 'DD/MM/YY HH24:MI:SS') as updated_at,
                    ST_AsGeoJSON(download_boundary)::json as geometry
                from projects
                where updated_at >= $1 and deleted_at = '-infinity'
            """, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select id from projects where deleted_at > $1
            """, syncedAt

        params.queryHash = () =>
            @db.jsonArrayQuery """
                select cid as id
                    , to_char(updated_at at time zone (projects.timezone), 'DD/MM/YY HH24:MI:SS') as updated_at
                from projects
                where deleted_at = '-infinity'
            """

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.downloadBoundaries
            clientHash: @hashes.downloadBoundaries
            syncedAt: @userSyncedAt


    # Get a list of project overlays if any of them changed since last position update was sent 
    # (otherwise, return an empty list)
    # Data level: project
    getUpdatedOverlays: =>
        @logs.messages.push "Getting overlays"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select id, name, properties, display_order
                    , to_char(overlays.updated_at at time zone (select timezone from projects where id = $1), 
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from overlays
                where project_id = $1 and updated_at >= $2 and deleted_at = '-infinity'
            """
            , @projectId, syncedAt
            .then (overlays) =>
                Promise.all R.map (overlay) =>
                    # Select all geometries for every new/updated overlay
                    @db.jsonArrayQuery """
                            select id, type, properties, ST_AsGeoJSON(geometry)::json as geometry
                            from geometries
                            where overlay_id = $1 and deleted_at = '-infinity'
                        """, overlay.id
                    .then (geometries) =>
                        R.merge overlay, geometries: geometries
                , overlays

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select id from overlays where project_id = $1 and deleted_at > $2
            """
            , @projectId, syncedAt

        params.queryHash = () =>
            @db.jsonArrayQuery """
                select id
                    , to_char(updated_at at time zone (select timezone from projects where id = $1), 
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from overlays
                where project_id = $1 and deleted_at = '-infinity'
            """
            , @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.overlays
            clientHash: @hashes.overlays
            syncedAt: @projectSyncedAt


    # Data level: project
    getUpdatedBaseLayers: =>
        @logs.messages.push "Getting updated base layers"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select map_id as id, max_zoom, display_order
                    , to_char(updated_at at time zone (select timezone from projects where id = $1), 
                        'DD/MM/YY HH24:MI:SS') as updated_at, max_native_zoom, type
                from base_layers
                where project_id = $1 and updated_at >= $2 and deleted_at = '-infinity'
            """
            , @projectId, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select map_id as id from base_layers where project_id = $1 and deleted_at > $2
            """
            , @projectId, syncedAt

        params.queryHash = () =>
            @db.jsonArrayQuery """
                select map_id as id
                    , to_char(updated_at at time zone (select timezone from projects where id = $1), 
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from base_layers
                where project_id = $1 and deleted_at = '-infinity'
            """
            , @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.baseLayers
            clientHash: @hashes.baseLayers
            syncedAt: @projectSyncedAt


    # Data level: project
    getUpdatedPermissions: =>
        @logs.messages.push "Getting updated permissions"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select permission as id
                    , to_char(updated_at at time zone (select timezone from projects where id = $2), 
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from permissions
                where user_id = $1 and project_id = $2 and updated_at >= $3 and deleted_at = '-infinity'
            """
            , @userId, @projectId, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select permission as id from permissions where user_id = $1 and project_id = $2 and deleted_at > $3
            """
            , @userId, @projectId, syncedAt

        params.queryHash = () =>
            @db.jsonArrayQuery """
                select permission::text as id
                    , to_char(updated_at at time zone (select timezone from projects where id = $2), 
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from permissions
                where user_id = $1 and project_id = $2 and deleted_at = '-infinity'
            """
            , @userId, @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.permissions
            clientHash: @hashes.permissions
            syncedAt: @projectSyncedAt


    # Data level: customer
    getUpdatedVehicles: =>
        @logs.messages.push "Getting updated vehicles list"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select number as id, rego, rego_exp_date, mileage, make, model
                    , to_char(updated_at at time zone (select timezone from projects where id = $1),
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from vehicles
                where customer_id = (select customer_id from projects where id = $1) and updated_at >= $2
                    and deleted_at = '-infinity'
            """
            , @projectId, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select number as id
                from vehicles
                where customer_id = (select customer_id from projects where id = $1) and deleted_at > $2
            """
            , @projectId, syncedAt

        params.queryHash = () =>
            @db.jsonArrayQuery """
                select number as id
                    , to_char(updated_at at time zone (select timezone from projects where id = $1),
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from vehicles
                where customer_id = (select customer_id from projects where id = $1) and deleted_at = '-infinity'
            """
            , @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.vehicles
            clientHash: @hashes.vehicles
            syncedAt: @userSyncedAt


    # Data level: project
    getUpdatedBeacons: =>
        @logs.messages.push "Getting updated beacons"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select beacons.id, beacon_uuid, major, minor, beacons.name, description
                    , role_id, beacon_roles.name as role_name
                    , to_char(beacons.updated_at at time zone (select timezone from projects where id = $1),
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from beacons
                join beacon_roles on role_id = beacon_roles.id
                where project_id = $1 and beacons.updated_at >= $2 and beacons.deleted_at = '-infinity'
            """
            , @projectId, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select id from beacons where project_id = $1 and deleted_at > $2
            """
            , @projectId, syncedAt

        params.queryHash = =>
            @db.jsonArrayQuery """
                select id, to_char(updated_at at time zone (select timezone from projects where id = $1),
                    'DD/MM/YY HH24:MI:SS') as updated_at
                from beacons
                where project_id = $1 and deleted_at = '-infinity'
            """
            , @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.beacons
            clientHash: @hashes.beacons
            syncedAt: @projectSyncedAt


    # Data level: customer
    getUpdatedBeaconRoles: =>
        @logs.messages.push "Getting beacon roles"

        params = {}
        params.queryAdded = (syncedAt) =>
            @db.jsonArrayQuery """
                select id, name
                    , to_char(updated_at at time zone (select timezone from projects where id = $1),
                        'DD/MM/YY HH24:MI:SS') as updated_at
                from beacon_roles
                where updated_at >= $2 and deleted_at = '-infinity'
            """, @projectId, syncedAt

        params.queryDeleted = (syncedAt) =>
            @db.jsonArrayQuery """
                select id from beacon_roles where deleted_at > $1
            """, syncedAt

        params.queryHash = =>
            @db.jsonArrayQuery """
                select id, to_char(updated_at at time zone (select timezone from projects where id = $1),
                    'DD/MM/YY HH24:MI:SS') as updated_at
                from beacon_roles
                where deleted_at = '-infinity'
            """, @projectId

        @getCollection R.merge params,
            fullSetRequired: @fullSetRequired.beaconRoles
            clientHash: @hashes.beaconRoles
            syncedAt: @userSyncedAt


canAlterUserPermissions = (hqPermissions, userPermission, projectId) ->
    projects = hqPermissions.permittedProjects
    (projects == "all" or R.contains projectId, projects) && (hqPermissions.cor || (userPermission != "signon" &&  hqPermissions.hr))


getPermissionString = (permission) ->
    permission.replace /[A-Z]/g, (match) ->
        "_" + match.toLowerCase()


module.exports = (helpers) ->
    sync: helpers.withErrorHandling (req, res) ->
        req.logs.request = util.abbrevArrays req.body

        reqParams = R.omit "data", req.body

        handlers = new SyncHandlers req.db.master, reqParams, req.body.data, req.logs


        # I didn't write something more clever because the order of calls is important - it encodes
        # the dependencies for setting up the response;
        # subqueues of items in the request have to be handled serially because
        # their order implies dependency (e.g. have to create user before saving their positions);
        # handlers object accumulates info from processing the data which can then be used by subsequent handlers;

        req.db.master.begin()
        .then =>
            handlers.getIdsFromCids()
        .then =>
            result = {}
            handlers.handleRequest("createUser", result)
        .then (result) =>
            handlers.handleRequest("updateUser", result)
        .then (result) =>
            handlers.handleRequest("requestFullSet", result)
        .then (result) =>
            handlers.getLastSyncTime().then => result  # Get the last position BEFORE we save the new batch of positions
        .then (result) =>
            handlers.handleRequest("recordPosition", result)
        .then (result) =>
            handlers.handleRequest("recordCred", result)
        .then (result) =>
            handlers.handleRequest("recordBeacon", result)
        .then (result) =>
            handlers.handleRequest("recordEvent", result)
        .then (result) =>
            handlers.handleRequest("recordBeaconEvent", result)
        .then (result) =>
            handlers.handleRequest("recordObservation", result)
        .then (result) =>
            handlers.handleRequest("recordAppStop", result)
        .then (result) =>
            handlers.handleRequest("recordAppStart", result)
        .then (result) =>
            handlers.handleRequest("recordUpload", result)
        .then (result) =>
            handlers.handleRequest("recordError", result)
        .then (result) =>
            handlers.handleRequest("recordDiagnostics", result)
        .then (result) =>
            handlers.handleRequest("recordVehicle", result)
        .then (result) =>
            handlers.getProjectId().then => result
        .then (result) =>
            handlers.updateUserProject().then => result
        .then (result) =>
            handlers.updateUserSyncedAt().then => result
        .then (responseData) =>
            handlers.addExtraResponseData(responseData)
        .then (result) =>
            req.db.master.commit().then =>
                req.logs.messages.push "Committed DB transaction"
                result
        .then (fullResponseData) =>
            req.logs.response = util.abbrevArrays fullResponseData
            res.json fullResponseData


    logError: helpers.withErrorHandling (req, res) ->
        req.db.master.query """
            insert into info_events (user_id, type, properties) values
                ((select id from users where cid = $1), 'error', $2::json)
        """
        , req.body.userId, JSON.stringify db.renameKeysForDb req.body.details
        .then ->
            res.json {}


    s3sign: helpers.withErrorHandling (req, res) ->
        req.logs.messages.push "s3sign params:", req.body

        bucketKey = switch req.body.bucket
            when "prestart_checklists" then "S3_BUCKET_PRESTART_CHECKLIST"
            else "S3_BUCKET_OBSERVATIONS"
        bucket = process.env[bucketKey]

        uid(18)
        .then (randomFileName) ->
            req.logs.messages.push "Setting AWS config"

            aws.config.update
                accessKeyId: process.env.AWS_ACCESS_KEY
                secretAccessKey: process.env.AWS_SECRET_KEY

            req.logs.messages.push "Getting signed S3 URL"
            s3 = new aws.S3()
            getSignedUrl = Promise.promisify(s3.getSignedUrl, s3)
            getSignedUrl "putObject",
                Bucket: bucket
                Key: randomFileName + ".jpg"
                Expires: 180
                ContentType: req.body.fileType
                ACL: "public-read"
            .then (signedRequestUrl) ->
                res.json
                    signedRequestUrl: signedRequestUrl
                    url: "https://#{bucket}.s3.amazonaws.com/#{randomFileName}.jpg"


    getAll: helpers.withErrorHandling (req, res) ->
        q = """
            select users.id as id, users.name as name, coalesce(nullif(user_roles.name,''), description) as role, company
            users join user_roles on users.role_id = user_roles.id
            order by name
        """

        req.db.master.jsonArrayQuery(q).then (result) ->
            res.json result


    permissions:
        createPermission: helpers.withErrorHandling (req, res) ->
            userPermission = getPermissionString req.body.permission
            queryUserApproval req
            .then (userId) ->
                if userId.approved && canAlterUserPermissions req.permissions, userPermission, req.params.projectId
                    req.db.master.query """
                        insert into permissions (project_id, user_id, permission) select $1, $2, $3
                        where not exists
                            (select * from permissions
                             where project_id = $1 and user_id = $2 and permission = $3 and deleted_at = '-infinity')
                    """
                    , req.params.projectId, req.params.id, userPermission
                    .then ->
                        res.json {}
                else
                    Promise.resolve(null).then -> res.status(403).send "Access denied"


        deletePermission: helpers.withErrorHandling (req, res) ->
            userPermission = getPermissionString req.body.permission
            queryUserApproval req
            .then (userId) ->
                if userId.approved && canAlterUserPermissions req.permissions, userPermission, req.params.projectId
                    req.db.master.query """
                        update permissions set deleted_at = now()
                        where project_id = $1 and user_id = $2 and deleted_at = '-infinity' and permission = $3
                    """
                    , req.params.projectId, req.params.id, userPermission
                    .then ->
                        res.json {}
                else
                    Promise.resolve(null).then -> res.status(403).send "Access denied"

