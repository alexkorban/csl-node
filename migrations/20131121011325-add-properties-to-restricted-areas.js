var dbm = require('db-migrate');
var type = dbm.dataType;
var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.addColumn.bind(db, 'restricted_areas', 'type',
            {type: 'string', defaultValue: 'Feature', notNull: true}),
        db.addColumn.bind(db, 'restricted_areas', 'properties',
            {type: 'json', notNull: true}),
        db.addColumn.bind(db, 'restricted_areas', 'project_id',
            {type: 'bigint', notNull: true}),
        db.renameColumn.bind(db, 'restricted_areas', 'area', 'geometry'),
        db.runSql.bind(db, 'alter table restricted_areas ' +
            "alter geometry type geometry(GEOMETRY, 4326)"),
        /*db.runSql.bind(db, "select UpdateGeometrySRID('restricted_areas', 'geometry', 4326)"),*/
        db.runSql.bind(db, 'alter table restricted_areas ' +
            'add constraint project_id_ref foreign key (project_id) references projects')
    ], callback);

};

exports.down = function(db, callback) {

};
