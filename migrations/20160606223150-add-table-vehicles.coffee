dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table vehicles (
            id bigserial primary key,
            number varchar not null,
            rego varchar not null,
            rego_exp_date date not null,
            mileage integer not null,
            make varchar not null,
            model varchar not null,
            customer_id bigint not null,
            created_at timestamp without time zone not null default now(),
            updated_at timestamp without time zone not null default now(),
            deleted_at timestamp without time zone not null default '-infinity'
        )
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop table if exists vehicles
    """, callback

