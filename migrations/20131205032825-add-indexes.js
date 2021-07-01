var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'create index positions_on_user_id_created_at on positions(user_id, created_at)'),
        db.runSql.bind(db, 'create index positions_on_project_id on positions(project_id)')
    ], callback);

};

exports.down = function(db, callback) {
//    async.series([
//        db.runSql.bind(db, 'drop index '),
//        db.removeColumn.bind(db, 'positions', 'project_id')
//    ], callback);

};
