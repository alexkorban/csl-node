var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.createTable("users", {
        ifNotExists: true,
        columns: {
            id: {type: "bigint", primaryKey: true, autoIncrement: true},
            name: {type: "string", notNull: true},
            created_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")},
            updated_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")}
        }
    }, callback);
};

exports.down = function(db, callback) {
    db.dropTable("users", callback);
};
