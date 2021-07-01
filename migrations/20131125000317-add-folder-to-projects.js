var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.addColumn('projects', 'folder', {type: "string", notNull: "true",
        defaultValue: "unknown"}, callback);

};

exports.down = function(db, callback) {

};
