dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table base_layers add max_native_zoom int not null default 17;
        create type base_layer_type as enum ('satellite', 'drone', 'linework');
        alter table base_layers add type base_layer_type not null default 'drone';
        update base_layers set type = 'satellite' where map_id = 'aoteastudios.mom2gn1f';
        update base_layers set type = 'linework' where drone_image = false and map_id != 'aoteastudios.mom2gn1f';
        alter table base_layers drop drone_image;
        alter table base_layers alter max_native_zoom drop default;
        alter table base_layers alter type drop default;
        update base_layers set max_native_zoom = max_zoom where type != 'satellite'


    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table base_layers add drone_image bool not null default false;
        update base_layers set drone_image = true where type = 'drone';
        alter table base_layers drop type, drop max_native_zoom;
        drop type if exists base_layer_type

    """, callback

