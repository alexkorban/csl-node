var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.createTable("positions", {
        ifNotExists: true,
        columns: {
            id: {type: "bigint", primaryKey: true, autoIncrement: true},
            user_id: {type: "bigint", notNull: true},
            lon: {type: "decimal(9,6)", notNull: true},
            lat: {type: "boolean", notNull: true},
            accuracy: {type: "integer"},
            created_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")},
        }
    }, callback);
};

exports.down = function(db, callback) {
    db.dropTable("positions", callback);
};
