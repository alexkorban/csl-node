var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'users', 'project_id', 'bigint'),
        db.runSql.bind(db, 'alter table users ' +
            'add constraint project_id_ref foreign key (project_id) references projects')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table users drop constraint project_id_ref'),
        db.removeColumn.bind(db, 'users', 'project_id')
    ], callback);

};
