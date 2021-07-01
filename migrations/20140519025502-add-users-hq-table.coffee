dbm = require 'db-migrate'

exports.up = (db, callback) ->
    db.runSql """
        create table users_hq (
        id bigserial primary key,
        email varchar(255) unique not null,
        password_hash varchar(255) not null)
    """, callback


exports.down = (db, callback) ->
    db.runSql "drop table if exists users_hq", callback

