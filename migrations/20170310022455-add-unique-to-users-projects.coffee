dbm = require "db-migrate"

exports.up = (db, callback) ->
    db.runSql """
        alter table users_projects add constraint users_projects_unique unique(project_id, user_id)
    """, callback


exports.down = (db, callback) ->
    db.runSql """
        alter table users_projects drop constraint users_projects_unique
    """, callback

