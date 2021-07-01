dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        CREATE OR REPLACE FUNCTION "json_object_set_key"(
          "json"          json,
          "key_to_set"    TEXT,
          "value_to_set"  anyelement
        )
          RETURNS json
          LANGUAGE sql
          IMMUTABLE
          STRICT
        AS $function$
        SELECT concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')::json
          FROM (SELECT *
                  FROM json_each("json")
                 WHERE "key" <> "key_to_set"
                 UNION ALL
                SELECT "key_to_set", to_json("value_to_set")) AS "fields"
        $function$;

        comment on function json_object_set_key(json, text, anyelement) is 'Adds or updates a value for a given key in a JSON object';

        CREATE OR REPLACE FUNCTION "json_object_set_keys"(
          "json"          json,
          "keys_to_set"   TEXT[],
          "values_to_set" anyarray
        )
          RETURNS json
          LANGUAGE sql
          IMMUTABLE
          STRICT
        AS $function$
        SELECT concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')::json
          FROM (SELECT *
                  FROM json_each("json")
                 WHERE "key" <> ALL ("keys_to_set")
                 UNION ALL
                SELECT DISTINCT ON ("keys_to_set"["index"])
                       "keys_to_set"["index"],
                       CASE
                         WHEN "values_to_set"["index"] IS NULL THEN 'null'::json
                         ELSE to_json("values_to_set"["index"])
                       END
                  FROM generate_subscripts("keys_to_set", 1) AS "keys"("index")
                  JOIN generate_subscripts("values_to_set", 1) AS "values"("index")
                 USING ("index")) AS "fields"
        $function$;

        comment on function json_object_set_keys(json, text[], anyarray) is 'Adds or updates multiple values for given keys in a JSON object';

        CREATE OR REPLACE FUNCTION "json_object_update_key"(
          "json"          json,
          "key_to_set"    TEXT,
          "value_to_set"  anyelement
        )
          RETURNS json
          LANGUAGE sql
          IMMUTABLE
          STRICT
        AS $function$
        SELECT CASE
          WHEN ("json" -> "key_to_set") IS NULL THEN "json"
          ELSE (SELECT concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')
                  FROM (SELECT *
                          FROM json_each("json")
                         WHERE "key" <> "key_to_set"
                         UNION ALL
                        SELECT "key_to_set", to_json("value_to_set")) AS "fields")::json
        END
        $function$;

        comment on function json_object_update_key(json, text, anyelement) is 'Updates a value for a given key in a JSON object (only if the key exists)';

        CREATE OR REPLACE FUNCTION "json_object_set_path"(
          "json"          json,
          "key_path"      TEXT[],
          "value_to_set"  anyelement
        )
          RETURNS json
          LANGUAGE sql
          IMMUTABLE
          STRICT
        AS $function$
        SELECT CASE COALESCE(array_length("key_path", 1), 0)
                 WHEN 0 THEN to_json("value_to_set")
                 WHEN 1 THEN "json_object_set_key"("json", "key_path"[l], "value_to_set")
                 ELSE "json_object_set_key"(
                   "json",
                   "key_path"[l],
                   "json_object_set_path"(
                     COALESCE(NULLIF(("json" -> "key_path"[l])::text, 'null'), '{}')::json,
                     "key_path"[l+1:u],
                     "value_to_set"
                   )
                 )
               END
          FROM array_lower("key_path", 1) l,
               array_upper("key_path", 1) u
        $function$;

        comment on function json_object_set_path(json, text[], anyelement) is 'Adds or updates a value at a given key-path in a JSON object';

    """, callback




exports.down = (db, callback) ->
    db.runSql """
        drop function if exists json_object_set_path(json, text[], anyelement);
        drop function if exists json_object_set_keys(json, text[], anyarray);
        drop function if exists json_object_update_key(json, text, anyelement);
        drop function if exists json_object_set_key(json, text, anyelement);
    """, callback

