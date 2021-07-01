dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create type beacon_events_json as (
	        type beacon_event_type,
	        created_at timestamp,
            beacon_id varchar,
            properties json,
            position json
        )
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop type beacon_events_json
    """, callback

