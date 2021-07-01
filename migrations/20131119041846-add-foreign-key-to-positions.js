var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.runSql("alter table positions " +
        "add constraint user_id_ref foreign key (user_id) references users", callback);
};

exports.down = function(db, callback) {
    db.runSql("alter table positions drop constraint user_id_ref", callback)
};
