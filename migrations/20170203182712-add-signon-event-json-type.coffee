dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create type signon_event_json as (
	        created_at timestamp,
            vehicle_id varchar,
            properties json,
            position json
        )
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop type signon_event_json
    """, callback

