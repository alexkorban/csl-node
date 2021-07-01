dbm = require "db-migrate"
R = require "ramda"

exports.up = (db, callback) ->
    roleData = [
        # First one is the default catch all role
        {"name": "",               "properties": {"is_machine":false, "does_paving":false}},

        # Normal roles as defined by the mobile app
        {"name": "Backhoe",        "properties": {"is_machine":true,  "does_paving":false}},
        {"name": "Community",      "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Concrete truck", "properties": {"is_machine":true,  "does_paving":true}},
        {"name": "Engineer",       "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Environment",    "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Foreman",        "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Grader",         "properties": {"is_machine":true,  "does_paving":false}},
        {"name": "Paver",          "properties": {"is_machine":true,  "does_paving":true}},
        {"name": "Safety",         "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Surveyor",       "properties": {"is_machine":false, "does_paving":false}},
        {"name": "Truck",          "properties": {"is_machine":true,  "does_paving":false}}
    ]

    sqlString = """
        -- setup the new roles table
        create table roles (
            id bigserial primary key,
            name varchar not null,
            properties json not null default '{}'
        );
        create unique index roles_name on roles (name);
    """

    # add all the roles so we can then refer to them from the user table.
    sqlString += R.reduce (acc, value) ->
        acc += "\ninsert into roles (name, properties) values ('" + value.name + "', '" + (JSON.stringify value.properties) + "');"
    , "", roleData

    sqlString += """
        -- add the foreign key to reference roles
        alter table users add role_id bigint not null default 0;
        alter table users add description varchar;
        update users set description = '';
        alter table users alter column description set not null;

        -- assign the correct role mappings to the existing users
        with role_mapping as (
            select users.id as uid, roles.id as rid from roles join users on roles.name = users.role
        )
        update users set role_id = role_mapping.rid from role_mapping where id = role_mapping.uid;

        -- Create a description for users without a valid role since we are going to drop the role column
        update users set description = (case when role is null then '' else role end) where role_id = 0;

        -- catch any users without a matching role and assign them the default so everyone has a valid role
        with default_role as (
            select roles.id from roles where name = ''
        )
        update users set role_id = default_role.id from default_role where users.role_id = 0;

        -- Now that all users have valid roles we can add the FK constraint
        alter table users add constraint role_id_ref foreign key (role_id) references roles(id);
        alter table users alter column role_id drop default;

        alter table users drop column role;
    """

    db.runSql sqlString, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users add role varchar;

        -- Reverse the role mapping assignments
        with role_mapping as (
            select users.id as uid, roles.name as role from users join roles on users.role_id = roles.id
        )
        update users set role = role_mapping.role from role_mapping where id = role_mapping.uid;
        update users set role = description where role = '';

        alter table users drop column if exists description;
        alter table users drop column if exists role_id;
        drop index if exists roles_name;
        drop table if exists roles;
    """, callback

