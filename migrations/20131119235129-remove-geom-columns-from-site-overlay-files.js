var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.removeColumn.bind(db, 'site_overlay_files', 'bbox'),
        db.removeColumn.bind(db, 'site_overlay_files', 'convex_hull')
    ], callback);

};

exports.down = function(db, callback) {
    console.log("IRREVERSIBLE_MIGRATION");
};
