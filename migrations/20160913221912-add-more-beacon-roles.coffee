dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        insert into beacon_roles (name) values ('Truck'), ('Light vehicle'), ('Machine'), ('Person')
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        update beacon_roles
        set deleted_at = clock_timestamp()
        where name in ('Truck', 'Light vehicle', 'Machine', 'Person')
    """, callback

