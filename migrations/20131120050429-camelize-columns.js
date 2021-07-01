var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

var _ = require('underscore')._;

camelize = function(s) {
    return s.replace(/(\-|_|\s)+(.)?/g, function(mathc, sep, c) {
        return (c ? c.toUpperCase() : '');
    });
}

underscorize = function(s) {
    s = s.replace(/([a-z\d])([A-Z]+)/g, '$1_$2').replace(/[-\s]+/g, '_').toLowerCase();
    if (s.charAt(0).isUpper()) {
        s = '_' + s;
    }
    return s;
}

// drop foreign keys
// rename columns
// rename tables
// create foreign keys



exports.up = function(db, callback) {
    db.runSql("select 1;", callback);
    return;

    var foreign_keys = [["positions", "user_id_ref"],
        ["site_overlay_files", "project_id_ref"],
        ["users", "project_id_ref"]];

    var columns = [["positions", "user_id"],
        ["positions", "created_at"],
        ["projects", "is_active"],
        ["projects", "created_at"],
        ["projects", "updated_at"],
        ["site_overlay_files", "project_id"],
        ["site_overlay_files", "created_at"],
        ["site_overlay_files", "updated_at"],
        ["users", "project_id"],
        ["users", "created_at"],
        ["users", "updated_at"]];

    var tables = ["site_overlay_files"];

    var new_foreign_keys = [["positions", "userIdRef", "userId", "users"],
        ["siteOverlayFiles", "projectIdRef", "projectId", "projects"],
        ["users", "projectIdRef", "projectId", "projects"]];

    var commands = _.map(foreign_keys, function(column) {
        return db.runSql.bind(db, "alter table " + column[0] + " drop constraint " + column[1]);
    });

    commands = commands.concat(
        _.map(columns, function(column) {
            return db.runSql.bind(db, "alter table " + column[0] + " rename column " + column[1] +
                " to " + camelize(column[1]));
        })
    );

    commands = commands.concat(
        _.map(tables, function(table) {
            return db.runSql.bind(db, "alter table " + table + " rename to " +
                camelize(table));
        })
    );

    commands = commands.concat(
        _.map(new_foreign_keys, function(column) {
            return db.runSql.bind(db, "alter table " + column[0] +
                " add constraint " + column[1] +
                " foreign key (" + column[2] + ") references " + column[3]);
        })
    );

    async.series(commands, callback);
};



exports.down = function(db, callback) {
    var foreign_keys = [["positions", "userIdRef"],
        ["siteoverlayfiles", "projectIdRef"],
        ["users", "projectIdRef"]];

    var columns = [["positions", "userid", "user_id"],
        ["positions", "createdat", "created_at"],
        ["projects", "isactive", "is_active"],
        ["projects", "createdat", "created_at"],
        ["projects", "updatedat", "updated_at"],
        ["siteoverlayfiles", "projectid", "project_id"],
        ["siteoverlayfiles", "createdat", "created_at"],
        ["siteoverlayfiles", "updatedat", "updated_at"],
        ["users", "projectid", "project_id"],
        ["users", "createdat", "created_at"],
        ["users", "updatedat", "updated_at"]];

    var tables = [["siteoverlayfiles", "site_overlay_files"]];

    var new_foreign_keys = [["positions", "user_id_ref", "user_id", "users"],
        ["site_overlay_files", "project_id_ref", "project_id", "projects"],
        ["users", "project_id_ref", "project_id", "projects"]];


    var commands = _.map(foreign_keys, function(column) {
        return db.runSql.bind(db, "alter table " + column[0] + " drop constraint if exists " + column[1]);
    });

    commands = commands.concat(
        _.map(columns, function(column) {
            return db.runSql.bind(db, "alter table " + column[0] + " rename column " + column[1] +
                " to " + column[2]);
        })
    );

    commands = commands.concat(
        _.map(tables, function(table) {
            return db.runSql.bind(db, "alter table " + table[0] + " rename to " +
                table[1]);
        })
    );

    commands = commands.concat(
        _.map(new_foreign_keys, function(column) {
            return db.runSql.bind(db, "alter table " + column[0] +
                " add constraint " + column[1] +
                " foreign key (" + column[2] + ") references " + column[3]);
        })
    );

    async.series(commands, callback);

};
