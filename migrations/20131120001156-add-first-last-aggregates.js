var dbm = require('db-migrate');
var type = dbm.dataType;

var async = require('async');

exports.up = function(db, callback) {
    async.series([
        db.runSql.bind(db,
            "-- Create a function that always returns the first non-NULL item      \n" +
            "CREATE OR REPLACE FUNCTION        first_agg ( anyelement, anyelement )\n" +
            "RETURNS anyelement LANGUAGE sql IMMUTABLE STRICT AS $$                \n" +
            "SELECT $1;                                                            \n" +
            "$$;                                                                   \n" +
            "                                                                      \n" +
            "-- And then wrap an aggregate around it                               \n" +
            "CREATE AGGREGATE first (                                              \n" +
            "    sfunc    = first_agg,                                             \n" +
            "    basetype = anyelement,                                            \n" +
            "    stype    = anyelement                                             \n" +
            ");                                                                    \n" +
            "                                                                      \n" +
            "-- Create a function that always returns the last non-NULL item       \n" +
            "CREATE OR REPLACE FUNCTION last_agg ( anyelement, anyelement )        \n" +
            "RETURNS anyelement LANGUAGE sql IMMUTABLE STRICT AS $$                \n" +
            "SELECT $2;                                                            \n" +
            "$$;                                                                   \n" +
            "                                                                      \n" +
            "-- And then wrap an aggregate around it                               \n" +
            "CREATE AGGREGATE last (                                               \n" +
            "    sfunc    = last_agg,                                              \n" +
            "    basetype = anyelement,                                            \n" +
            "    stype    = anyelement                                             \n" +
            ");"
    )], callback);
};

exports.down = function(db, callback) {
    async.series([
        db.runSql.bind(db,
        'drop aggregate if exists first(anyelement);' +
        'drop function if exists first_agg(anyelement, anyelement);' +
        'drop aggregate if exists last(anyelement);' +
        'drop function if exists last_agg(anyelement, anyelement);')
    ], callback);
};



