var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.changeColumn.bind(db, 'restricted_areas', 'geometry',
            {notNull: true}),
        db.changeColumn.bind(db, 'restricted_areas', 'created_at',
            {notNull: true, defaultValue: new String("now()")}),
        db.changeColumn.bind(db, 'restricted_areas', 'updated_at',
            {notNull: true, defaultValue: new String("now()")})
    ], callback);

};

exports.down = function(db, callback) {

};
