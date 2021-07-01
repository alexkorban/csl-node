var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.createTable.bind(db, 'overlays',
            {id: {type: 'bigint', primaryKey: true},
             name: {type: 'string', notNull: true, defaultValue: 'unnamed'},
             is_editable: {type: 'boolean', notNull: true, defaultValue: false}
            })
    ], callback);

};

exports.down = function(db, callback) {

};
