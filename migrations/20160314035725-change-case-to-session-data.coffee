dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        update sessions
            set data = ('{"is_authenticated":' || (data::json->>'isAuthenticated') ||
                ', "user_id": '|| (data::json->>'userId') || '}')::json
        where (data::json->>'isAuthenticated') is not null
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        update sessions
        set data = ('{"isAuthenticated":' || (data::json->>'is_authenticated') ||
            ', "userId": '|| (data::json->>'user_id') || '}')::json
        where (data::json->>'is_authenticated') is not null
    """, callback

