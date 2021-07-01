var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db, "CREATE TYPE event_type AS ENUM ('entry', 'exit')"),
        db.createTable.bind(db, 'events', {
            id: {type: 'bigint', primaryKey: true, autoIncrement: true},
            type: {type: 'event_type', notNull: true},
            properties: {type: 'json', notNull: true, defaultValue: new String("'{}'::json")},
            user_id: {type: 'bigint', notNull: true},
            project_id: {type: 'bigint', notNull: true},
            created_at: {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")},
            updated_at: {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")},
            recorded_at: {type: "timestamp with time zone", notNull: true, defaultValue: new String("now()")}
        }),
        db.runSql.bind(db, 'alter table events ' +
            'add constraint project_id_ref foreign key (project_id) references projects'),
        db.runSql.bind(db, 'alter table events ' +
            'add constraint user_id_ref foreign key (user_id) references users')

    ], callback);

};

exports.down = function(db, callback) {

};
