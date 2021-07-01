dbm = require('db-migrate')
async = require('async')
type = dbm.dataType

exports.up = (db, callback) ->
    async.series [
        db.runSql.bind(db, """
            CREATE TABLE "session" (
              "sid" varchar NOT NULL COLLATE "default",
                "sess" json NOT NULL,
                "expire" timestamp(6) NOT NULL
            )
            WITH (OIDS=FALSE);
            ALTER TABLE session ADD CONSTRAINT "session_pkey" PRIMARY KEY ("sid") NOT DEFERRABLE INITIALLY IMMEDIATE;
        """)
    ], callback


exports.down = (db, callback) ->
    async.series [
        db.runSql.bind(db, 'drop table if exists "session"')
    ], callback

