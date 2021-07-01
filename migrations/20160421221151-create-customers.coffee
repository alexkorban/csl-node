dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create table customers (
            id bigserial primary key,
            name varchar not null,
            properties json not null,
            created_at timestamp with time zone not null default now(),
            updated_at timestamp with time zone not null default now(),
            deleted_at timestamp with time zone not null default '-infinity'
        );

        insert into customers (name, properties) values ('Lendlease', '{}');

        alter table projects
            add column customer_id bigint,
            add constraint customer_id_ref foreign key (customer_id) references customers;
        update projects set customer_id = (select id from customers);
        alter table projects alter customer_id set not null;

        alter table users_hq
            add column customer_id bigint,
            add constraint customer_id_ref foreign key (customer_id) references customers;
        update users_hq set customer_id = (select id from customers);
        alter table users_hq alter customer_id set not null;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects
            drop constraint if exists customer_id_ref,
            drop column if exists customer_id;
        alter table users_hq
            drop constraint if exists customer_id_ref,
            drop column if exists customer_id;
        drop table if exists customers
    """, callback

