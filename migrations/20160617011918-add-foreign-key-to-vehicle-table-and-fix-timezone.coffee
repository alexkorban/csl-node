dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table vehicles alter column created_at set data type timestamp with time zone,
                             alter column updated_at set data type timestamp with time zone,
                             alter column deleted_at set data type timestamp with time zone,
                             add constraint customer_id_ref foreign key (customer_id) references customers
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table vehicles alter column created_at set data type timestamp without time zone,
                             alter column updated_at set data type timestamp without time zone,
                             alter column deleted_at set data type timestamp without time zone,
                             drop constraint customer_id_ref
    """, callback
