dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        create function timestamp_overlay()
            returns trigger
            as $$
                declare overlay_id bigint;
                begin
                    if (TG_OP = 'DELETE') then
                        overlay_id = OLD.overlay_id;
                    else
                        overlay_id = NEW.overlay_id;
                    end if;
                    update overlays set updated_at = clock_timestamp() where id = overlay_id;
                    return null;
                end;
            $$ language plpgsql;

        create trigger geometry_changed
            after insert or update or delete on geometries
            for each row execute procedure timestamp_overlay();

    """, callback


exports.down = (db, callback) ->
    db.runSql """
        drop trigger geometry_changed on geometries;
        drop function timestamp_overlay();
    """, callback

