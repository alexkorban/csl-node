var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

var _ = require('underscore')._;

var columns = [["positions", "created_at"],
                ["projects", "created_at"],
                ["projects", "updated_at"],
                ["site_overlay_files", "created_at"],
                ["site_overlay_files", "updated_at"],
                ["users", "created_at"],
                ["users", "updated_at"]];

exports.up = function(db, callback) {
    commands = _.map(columns, function(column) {
        return db.runSql.bind(db, "alter table " + column[0] + " alter " + column[1] + " type timestamp with time zone");
    });

    async.series(commands, callback);

};

exports.down = function(db, callback) {
    commands = _.map(columns, function(column) {
        return db.runSql.bind(db, "alter table " + column[0] + " alter " + column[1] + " type timestamp without time zone");
    });

    async.series(commands, callback);
};
