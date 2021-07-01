var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table positions add project_id bigint'),
        db.runSql.bind(db, 'update positions set project_id = (select id from projects limit 1)'),
        db.runSql.bind(db, 'alter table positions alter project_id set not null'),
        db.runSql.bind(db, 'alter table positions ' +
            'add constraint project_id_ref foreign key (project_id) references projects')
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, 'alter table positions drop constraint project_id_ref'),
        db.removeColumn.bind(db, 'positions', 'project_id')
    ], callback);

};
