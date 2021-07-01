dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update overlays set properties = '{"marker":{"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"},"polygon":{"weight":2,"fill":true,"fillColor":"#79acdc","lineJoin":"round","opacity":0.75,"fillOpacity":0,"color":"#ffffff"}}', updated_at = now()
        where name = 'User defined areas'
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        update overlays set properties = '{"marker":{"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"},"polygon":{"weight":2,"fill":true,"fillColor":"#79acdc","lineJoin":"round","opacity":0.75,"fillOpacity":0,"color":"#ffa500"}}', updated_at = now()
        where name = 'User defined areas'
    """, callback

