dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table vehicles add beacon_id bigint references beacons;

        alter table vehicles add cid varchar(24);
        update vehicles set cid = array_to_string(array(select chr((65 + round((random() + id - id) * 25))::integer)
                                                        from generate_series(1, 6)), '');
        alter table vehicles alter cid set not null, add unique(cid);

        alter table beacons add cid varchar(24);
        update beacons set cid = array_to_string(array(select chr((65 + round((random() + id - id) * 25))::integer)
                                                       from generate_series(1, 6)), '');
        alter table beacons alter cid set not null, add unique(cid);
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table vehicles drop beacon_id, drop cid;
        alter table beacons drop cid;
    """, callback

