dbm = require('db-migrate')
async = require('async')
type = dbm.dataType

exports.up = (db, callback) ->
    async.series [
        db.runSql.bind(db, "alter table positions add speed real not null default 0")
        db.runSql.bind(db, "alter table positions alter speed drop default")
        db.runSql.bind(db, "alter table positions add heading real not null default 0")
        db.runSql.bind(db, "alter table positions alter heading drop default")
    ], callback


exports.down = (db, callback) ->
    async.series [
        db.runSql.bind(db, "alter table positions drop heading")
        db.runSql.bind(db, "alter table positions drop speed")
    ], callback

