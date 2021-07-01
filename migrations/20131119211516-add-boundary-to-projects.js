var dbm = require('db-migrate');
var type = dbm.dataType;
var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'projects', 'bbox', 'box2d'),
        db.addColumn.bind(db, 'projects', 'boundary', 'geometry(POLYGON, 4326)')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.removeColumn.bind(db, 'projects', 'bbox'),
        db.removeColumn.bind(db, 'projects', 'boundary')
    ], callback);

};
