dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table events add position json, add geometry_id bigint, add geometry_name varchar(255),
            add constraint geometry_id_ref foreign key (geometry_id) references geometries;
        update events set position = properties->'position' where type = 'jha';
        update events set geometry_id = (properties->>'geometry_id')::bigint, geometry_name = properties->>'geometry_name'
            where (type = 'entry' or type = 'exit') and (properties->>'geometry_id')::bigint in (select id from geometries);

    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table events drop position, drop geometry_id, drop geometry_name
    """, callback

