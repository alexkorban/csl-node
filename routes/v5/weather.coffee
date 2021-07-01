module.exports = (helpers) ->
    saveWeather: helpers.withErrorHandling (req, res) ->
        req.db.master.query """
            with array_json as
                (select * from json_populate_recordset (null::weather, ($1)::json) as incoming_records
                    where not exists
                    (select 1 from weather
                    where weather.lon = incoming_records.lon
                    and weather.lat = incoming_records.lat
                    and weather.created_at = incoming_records.created_at)
                )
            insert into weather (name, created_at, lon, lat, air_temp, pressure, cloud, visibility, press_tend, rain_trace, gust_speed, humidity, wind_dir, wind_speed)
            select name, created_at, lon, lat, air_temp, pressure, cloud, visibility, press_tend, rain_trace, gust_speed, humidity, wind_dir, wind_speed
            from array_json;
        """
        , JSON.stringify db.renameKeysForDb req.body
        .then ->
            res.json {}

    getWeather: helpers.withErrorHandling (req, res) ->
        req.db.follower.jsonQuery """
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
        , req.params.projectId
        .then (result) ->
            res.json result


