var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'positions', 'recorded_at',
            {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")}),
        db.runSql.bind(db, 'update positions set recorded_at = created_at')
    ], callback);

};

exports.down = function(db, callback) {

};
