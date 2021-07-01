var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'site_overlay_files', 'project_id', 'bigint'),
        db.runSql.bind(db, 'alter table site_overlay_files ' +
            'add constraint project_id_ref foreign key (project_id) references projects')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table site_overlay_files drop constraint project_id_ref'),
        db.removeColumn.bind(db, 'site_overlay_files', 'project_id')
    ], callback);

};
