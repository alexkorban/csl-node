var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'overlays', 'created_at',
            {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")}),
        db.addColumn.bind(db, 'overlays', 'updated_at',
            {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")})
    ], callback);

};

exports.down = function(db, callback) {

};
