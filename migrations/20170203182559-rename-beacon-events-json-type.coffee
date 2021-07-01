dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter type beacon_events_json rename to beacon_event_json
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter type beacon_event_json rename to beacon_events_json
    """, callback

