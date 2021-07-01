dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create or replace function "json_object_del_key"(
          "json"          json,
          "key_to_del"    text
        )
          returns json
          language sql
          immutable
          strict
        as $function$
        select case
          when ("json" -> "key_to_del") is null then "json"
          else (select concat('{', string_agg(to_json("key") || ':' || "value", ','), '}')
                  from (select *
                          from json_each("json")
                         where "key" <> "key_to_del"
                       ) as "fields")::json
        end
        $function$;
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop function if exists json_object_del_key(json, text);
    """, callback

