var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'site_overlay_files', 'display_order', {type: "integer", notNull: "true",
            defaultValue: 0})
    ], callback);

};

exports.down = function(db, callback) {

};
