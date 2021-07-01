module.exports = (helpers) ->
    test: helpers.withErrorHandling (req, res) ->
        res.json {query: req.query, params: req.params, body:req.body, locals: express().locals}

    genPositions: helpers.withErrorHandling (req, res) ->
        req.db.master.query """
            insert into positions(created_at, recorded_at, lon, lat, project_id, user_id, accuracy, speed, heading)
            with seq as
            (
                select $4::float as row_count, generate_series(0,$4::integer) as index, random()*($5::float) as noise
            ),
            points as
            (
                select *,
                    (select ST_Project(
                            ST_LineInterpolatePoint(geometry,$10::float + (($11::float - $10::float) * (seq.index/seq.row_count)))
                            ,noise,random()*2.0*pi())
                    from geometries where id = $1)
                    as point
                from seq
            )
            select
                $9::timestamp + ($6::interval)*(index/row_count) as created_at,
                $9::timestamp + ($6::interval)*(index/row_count) as recorded_at,
                ST_X(point::geometry) as lon,
                ST_Y(point::geometry) as lat,
                $2::integer as project_id,
                $3::integer as user_id,
                1+round(noise*1.3)::integer as accuracy,
                $7::real as speed,
                $8::real as heading
            from points
            """,
            req.body.geometry,              # geometry id to use as a guiding line
            req.body.project,               # project id to insert positions under
            req.body.user,                  # user id to insert positions as
            (req.body.positions ? 10)-1,    # number of points to generate in total
            req.body.noise ? 0,             # random position variability in meters (affects accuracy values)
            req.body.duration ? "1 minute", # total interval over which to generate all positions
            req.body.speed ? 1.0,           # speed value to use for all positions
            req.body.heading ? 0.0          # heading value to use for all positions
            req.body.startAt ? (new Date).toISOString() # time stamp of the first position in postgres timestamp format
            req.body.start ? 0.0            # [0-1] fraction of the line to start at
            req.body.end ? 1.0              # [0-1] fraction of the line to end at (can be less than start to reverse travel)
        .then (result) ->
            res.json result

