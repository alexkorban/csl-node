dbm = require "db-migrate"
R = require "ramda"

addCorToReports = (item, type) ->
    transformations =
        reports:
            if type == "project"
                R.assoc "breaks", (item.cor ? false)
            else
                R.assoc("breaks", item.cor) if item.cor?
    R.pipe(R.evolve(transformations), R.omit(["cor"])) item

removeCorFromReports = (item, type) ->
    maybeCor = (item) ->
        cor = R.path ["reports", "breaks"], item
        if cor
            R.assoc "cor", cor, item
        else
            item
    transformations =
        reports:
            if type == "project"
                R.assoc "breaks", true
            else
                R.omit ["breaks"]
    R.pipe(maybeCor, R.evolve(transformations)) item


exports.up = (db, callback) ->
    db.all """
        select id, permissions from users_hq;
    """, (err, result) ->
        q = (R.map (user) ->
            permissions = R.map ((item) -> addCorToReports item, "user"), user.permissions
            console.log "P", permissions
            """update users_hq set permissions = '#{JSON.stringify permissions}' where id = #{user.id};"""
        , result).join(" ")
        db.runSql q, ->
            db.all """
                select id, permissions from projects;
            """, (err, result) ->
                q = (R.map (project) ->
                    permissions = addCorToReports project.permissions, "project"
                    """update projects set permissions = '#{JSON.stringify permissions}' where id = #{project.id};"""
                , result).join("")
                db.runSql q, callback



exports.down = (db, callback) ->
    db.all """
        select id, permissions from users_hq;
    """, (err, result) ->
        q = (R.map (user) ->
            permissions = R.map  ((item) -> removeCorFromReports item, "user"), user.permissions
            """update users_hq set permissions = '#{JSON.stringify permissions}' where id = #{user.id};"""
        , result).join(" ")
        db.runSql q, ->
            db.all """
                select id, permissions from projects;
            """, (err, result) ->
                q = (R.map (project) ->
                    permissions = removeCorFromReports project.permissions, "project"
                    """update projects set permissions = '#{JSON.stringify permissions}' where id = #{project.id};"""
                , result).join("")
                db.runSql q, callback
