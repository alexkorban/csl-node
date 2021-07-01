dbm = require "db-migrate"
R = require "ramda"

exports.up = (db, callback) ->
    db.all """
        select id, permissions from users_hq;
    """, (err, result) ->
        q = """
            alter table projects add permissions json not null default '{}';
            update projects set permissions = '{"drawing":true,"reports":{"areas":true,"breaks":true,"concrete_tests":true,"driver_fitness":true,"load_counts":true,"project_visits":true,"speed_bands":true,"timeline":true}}';
        """
        R.forEach (user) ->
            reports =
                if user.permissions.reports == "[]"
                    { areas: false, breaks: false, concrete_tests: false, driver_fitness: false, load_counts: false, project_visits: false, speed_bands: false, timeline: false }
                else
                    {}
            permissions =
                if user.permissions.projects == "all"
                    { all: {}, 17:  { hr: true, cor: true, paving: true, reports: reports }}
                else
                    userPermissions = R.pipe(R.merge, R.omit(["projects"])) user.permissions, reports: reports
                    R.mergeAll R.map ((projectId) -> "#{projectId}": userPermissions), user.permissions.projects

            q += "update users_hq set permissions = '#{JSON.stringify permissions}' where id = #{user.id};"
        , result
        db.runSql q, callback


exports.down = (db, callback) ->
    db.all """
        select id, permissions from users_hq;
    """, (err, result) ->
        q = "alter table projects drop permissions;"
        R.forEach (user) ->
            projects =
                if R.has "all", user.permissions
                    "all"
                else
                    R.map ((key) -> parseInt key), R.keys user.permissions
            permissions = { projects: projects, reports: "all", drawing: true }
            q += "update users_hq set permissions = '#{JSON.stringify permissions}' where id = #{user.id};"
        , result
        db.runSql q, callback
