var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'overlays', 'properties',
            {type: 'json', notNull: true, defaultValue: new String("'{}'::json")}),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#ff7800", "weight": 3, "opacity": 0.65, "fill": true, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "red", "iconColor": "white"}}\'::json where name = \'Hazards\''),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#0000aa", "weight": 2, "opacity": 0.65, "fill": true, "fillColor": "0000aa", "fillOpacity": 0.33, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"}}\'::json where name = \'Cut\''),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#aa0000", "weight": 2, "opacity": 0.65, "fill": true, "fillColor": "aa0000", "fillOpacity": 0.33, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"}}\'::json where name = \'Fill\''),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#79acdc", "weight": 2, "opacity": 0.35, "fill": true, "fillColor": "79acdc", "fillOpacity": 0.25, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"}}\'::json where name = \'Boundary\''),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#ff6498", "weight": 3, "opacity": 0.65, "fill": true, "fillColor": "ff6498", "fillOpacity": 0.33, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"}}\'::json where name = \'Heritage areas\''),
        db.runSql.bind(db, 'update overlays set properties = \'{"polygon": {"color": "#ff7800", "weight": 3, "opacity": 0.65, "fill": true, "fillColor": "ff7800", "fillOpacity": 0.33, "lineJoin": "round"}, "marker": {"icon": "exclamation", "prefix": "fa", "markerColor": "blue", "iconColor": "white"}}\'::json where name = \'Clearing line\'')

    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.removeColumn.bind(db, 'overlays', 'properties')
    ], callback);
};
