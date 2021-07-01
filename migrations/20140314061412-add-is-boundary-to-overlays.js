var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'overlays', 'is_boundary', {type: 'boolean', defaultValue: 'false', notNull: true})
    ], callback);

};

exports.down = function(db, callback) {

};
