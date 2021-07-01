dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        insert into overlays (name, project_id, display_order, properties)
            select 'Field observations',
                   id,
                   30,
                  '{"marker":{"icon": "exclamation-triangle", "prefix": "fa", "markerColor": "transparent", "iconColor": "#FFA63B"},"polygon":{"weight":2,"fill":true,"fillColor":"#79acdc","lineJoin":"round","opacity":0.75,"fillOpacity":0,"color":"#ffffff"}}'
            from projects
            where id not in (select project_id from overlays where name = 'Field observations');
    """, callback

exports.down = (db, callback) ->
    # This will only work if there are no geometries associated with these overlays
    db.runSql """
        delete from overlays where name = 'Field observations';
    """, callback
