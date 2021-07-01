dbm = require('db-migrate')
async = require('async')
type = dbm.dataType

exports.up = (db, callback) ->
    async.series [
        db.runSql.bind(db, "alter table users add synced_at timestamp with time zone not null default '-infinity'")
    ], callback


exports.down = (db, callback) ->
    async.series [
        db.runSql.bind(db, "alter table users drop synced_at")
    ], callback

