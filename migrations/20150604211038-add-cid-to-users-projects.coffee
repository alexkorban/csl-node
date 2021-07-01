dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users add cid varchar(24);
        update users set cid = array_to_string(ARRAY(SELECT chr((65 + round((random()+id-id) * 25)) :: integer) FROM generate_series(1,6)), '');
        alter table users alter cid set not null, add unique(cid);
        alter table projects add cid varchar(24);
        update projects set cid = array_to_string(ARRAY(SELECT chr((65 + round((random()+id-id) * 25)) :: integer) FROM generate_series(1,6)), '');
        alter table projects alter cid set not null, add unique(cid);
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table projects drop cid;
        alter table users drop cid;
    """, callback

