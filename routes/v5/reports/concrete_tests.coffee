module.exports = (req) ->
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
