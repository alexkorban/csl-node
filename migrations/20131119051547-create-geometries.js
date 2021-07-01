var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.createTable("geometries", {
        ifNotExists: true,
        columns: {
            id: {type: "bigint", primaryKey: true, autoIncrement: true},
            name: {type: "string"},
            key: {type: "string"},
            geom: "geometry"
        }
    }, callback);
};

exports.down = function(db, callback) {
    db.dropTable("geometries", callback);
};

