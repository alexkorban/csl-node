dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        drop aggregate if exists first(anyelement);
        drop aggregate if exists last(anyelement);

        -- Create transition function for first aggregate
        CREATE OR REPLACE FUNCTION first_agg(anyarray, anyelement)
          RETURNS anyarray AS
        $$
            SELECT CASE WHEN array_upper($1,1) IS NULL THEN array_append($1,$2) ELSE $1 END;
        $$
          LANGUAGE 'sql' IMMUTABLE;

        -- Create final transition function for first aggregate
        CREATE OR REPLACE FUNCTION first_agg_final(anyarray)
          RETURNS anyelement AS
        $$
            SELECT ($1)[1] ;
        $$
          LANGUAGE 'sql' IMMUTABLE;

        -- And then wrap an aggregate around it
        CREATE AGGREGATE first (
            sfunc     = first_agg,
            finalfunc = first_agg_final,
            basetype  = anyelement,
            stype     = anyarray
        );

        -- Create a function that always returns the last item (NULLs included)
        CREATE OR REPLACE FUNCTION last_agg ( anyelement, anyelement )
        RETURNS anyelement LANGUAGE sql IMMUTABLE AS $$
        SELECT $2;
        $$;

        -- And then wrap an aggregate around it
        CREATE AGGREGATE last (
            sfunc    = last_agg,
            basetype = anyelement,
            stype    = anyelement
        );
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop aggregate if exists first(anyelement);
        drop aggregate if exists last(anyelement);
        drop function if exists first_agg_final(anyelement, anyelement);

        -- Create a function that always returns the first non-NULL item
        CREATE OR REPLACE FUNCTION first_agg ( anyelement, anyelement )
        RETURNS anyelement LANGUAGE sql IMMUTABLE STRICT AS $$
        SELECT $1;
        $$;

        -- And then wrap an aggregate around it
        CREATE AGGREGATE first (
            sfunc    = first_agg,
            basetype = anyelement,
            stype    = anyelement
        );

        -- Create a function that always returns the last non-NULL item
        CREATE OR REPLACE FUNCTION last_agg ( anyelement, anyelement )
        RETURNS anyelement LANGUAGE sql IMMUTABLE STRICT AS $$
        SELECT $2;
        $$;

        -- And then wrap an aggregate around it
        CREATE AGGREGATE last (
            sfunc    = last_agg,
            basetype = anyelement,
            stype    = anyelement
        );
    """, callback

