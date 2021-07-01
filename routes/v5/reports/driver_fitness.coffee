module.exports = (req) ->
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
                user_roles.name as user_role,
                coalesce(permissions.permissions, '[]'::json) as permissions,
                vehicles.number as vehicle_number, vehicles.role_id as vehicle_role_id
            from signon_events
            join users on users.id = user_id
            join user_roles on users.role_id = user_roles.id
            left join vehicles on vehicles.id = signon_events.vehicle_id
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
        select date, time, user_name, signons.properties, permissions,
            (case when user_role in ('Truck', 'Concrete truck') then user_role else vehicle_roles.name end) as vehicle_type,
            (case when user_role in ('Truck', 'Concrete truck') then signons.properties->>'truck_number'
                else  signons.vehicle_number end) as vehicle_number
        from signons
        left join vehicle_roles on vehicle_roles.id = signons.vehicle_role_id
    """
    , req.params.projectId
    , req.query.userId
    , req.query.roleId
    , req.query.dateRange[0], req.query.dateRange[1]
