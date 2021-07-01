var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.createTable("projects", {
        ifNotExists: true,
        columns: {
            id: {type: "bigint", primaryKey: true, autoIncrement: true},
            name: {type: "string", notNull: true, defaultValue: "Unnamed project"},
            is_active: {type: "boolean", notNull: true, defaultValue: "t"},
            created_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")},
            updated_at: {type: "timestamp without time zone", notNull: true, defaultValue: new String("now()")}
        }
    }, callback);
};

exports.down = function(db, callback) {
    db.dropTable("projects", callback);
};
