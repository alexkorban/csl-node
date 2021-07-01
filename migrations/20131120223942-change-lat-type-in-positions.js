var dbm = require('db-migrate');
var type = dbm.dataType;

exports.up = function(db, callback) {
    db.runSql("alter table positions alter lat type decimal(9,6) using null", callback);
};

exports.down = function(db, callback) {

};
