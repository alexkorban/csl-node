var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "create table notifications (" +
            "id bigserial primary key, " +
            "recipients json not null default '{}'::json, " +
            "project_id bigint not null, " +
            "constraint project_id_ref foreign key (project_id) references projects)"

        )
    ], callback);

};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db, "drop table if exists notifications")
    ], callback);

};
