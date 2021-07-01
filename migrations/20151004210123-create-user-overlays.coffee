dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        insert into overlays (name, project_id, display_order, properties)
            select 'User defined areas',
                   id,
                   40,
                  '{"marker":{"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"},"polygon":{"weight":2,"fill":true,"fillColor":"#79acdc","lineJoin":"round","opacity":0.75,"fillOpacity":0,"color":"#ffa500"}}'
            from projects
            where id not in (select project_id from overlays where name = 'User defined areas');
    """, callback

exports.down = (db, callback) ->
    db.runSql """
        delete from geometries where overlay_id in (select id from overlays where name = 'User defined areas');
        delete from overlays where name = 'User defined areas';
    """, callback
