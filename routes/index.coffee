helpers = require "./helpers"
mware = require "../middleware"

exports.attachTo = (app) ->

    app.all "*", mware.setupLogs, mware.checkOrigin, mware.connectToDb

    # Test route for Uptime Robot and sanity checks
    index = helpers.withErrorHandling (req, res) ->
        q = """
            select '{"status": "Up"}'::json as response where $1
        """
        req.db.master.jsonQuery(q, true).then (result) ->
            res.json result

    # Note: no auth
    app.get "/", index

    # Note: no auth
    app.get "/ping", (req, res) ->
        res.json status: "Express up"

    # Loads a file with route handlers for a given API version
    requireHandlers = R.curry (version, name) -> [name, require("./#{version}/#{S(name).underscore().s}")(helpers)]

    # Note: the sets of files loaded for each version can differ
    routeHandlers = {}
    routeHandlers.v4 = R.fromPairs R.map requireHandlers("v4")
        , ["user", "project", "userHq", "paving", "reports", "weather", "internal", "development"]
    routeHandlers.v5 = R.fromPairs R.map requireHandlers("v5")
        , ["users", "projects", "usersHq", "paving", "reports", "weather", "internal", "development"]

    # Redirecting to the previous version of the API isn't an option for preflighted
    # CORS requests, therefore each version of the API has to have handlers defined
    # explicitly for all endpoints. So the solution is to assign handlers explicitly,
    # using previous handlers from the previous version(s) where there was no change
    R.forEach ((version) -> app.use "/#{version}", require("./#{version}")(mware, routeHandlers[version]))
    , ["v4", "v5"]

    # Catch all retired versions
    app.use /\/v\d+/, (req, res) ->
        res.status(410).send ""

    # Catch all clause for errors; note that non-existent routes 404 by default
    app.use (err, req, res, next) ->
        if err?
            console.info "Server error: #{err.message}"
            console.info err.stack
            res.status(500).send "Something broke!"
