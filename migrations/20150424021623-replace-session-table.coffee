dbm = require 'db-migrate'

exports.up = (db, callback) ->
    db.runSql """
        drop table if exists "session";
        create table sessions (
            id varchar(24) primary key,
            data json not null,
            created_at timestamp not null default now(),
            updated_at timestamp not null default now()
        )
    """, callback

exports.down = (db, callback) ->
    db.runSql """
        drop table if exists sessions;
        CREATE TABLE "session" (
          "sid" varchar NOT NULL COLLATE "default",
            "sess" json NOT NULL,
            "expire" timestamp(6) NOT NULL
        )
        WITH (OIDS=FALSE);
        ALTER TABLE session ADD CONSTRAINT "session_pkey" PRIMARY KEY ("sid") NOT DEFERRABLE INITIALLY IMMEDIATE;
    """, callback

