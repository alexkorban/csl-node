#
# custom middleware
#

exports.setupLogs = (req, res, next) ->
    req.logs = messages: []
    next()


exports.checkOrigin = (req, res, next) ->
    if process.env.NODE_ENV != "dev" && req.headers['x-forwarded-proto'] != 'https'
        res.status(403).send "HTTPS required"
        return

    #console.log "middleware: checkOrigin"
    origin = req.header("Origin") || ""
    #console.log "Headers: " + JSON.stringify(req.headers)

    originIsOk = req.url == "/" || origin == "" || process.env.NODE_ENV == "dev" ||
        S(origin).startsWith("chrome-extension://") ||
        (origin == "https://csl-safesitehq-staging.herokuapp.com" && process.env.NODE_ENV == "staging") ||
        (origin == "https://www.myvirtualsuper.com" && process.env.NODE_ENV == "production") ||
        ((S(origin).startsWith("http://localhost") || S(origin).startsWith("http://127.0.0.1") || S(origin).startsWith("file://")) &&
            (req.method == "OPTIONS" || req.header("x-sf-token") == process.env.CSL_REQUEST_TOKEN))

    if originIsOk
        res.header "Access-Control-Allow-Origin", origin
        res.header "Access-Control-Allow-Headers", "Accept,Origin,SessionID,X-SF-Token,X-Requested-With,Content-Type"
        res.header "Access-Control-Allow-Methods", "GET,PUT,POST,DELETE,OPTIONS"
        res.header "Access-Control-Allow-Credentials", true
        next()
    else
        res.status(403).send "Origin checks failed for #{origin}"


exports.checkAuth = (req, res, next) ->
    if req.session.data.isAuthenticated
        next()
    else
        res.status(401).send "Authentication failed"


exports.authorise = (req, res, next) ->
    projectId = parseInt req.params.projectId if req.params.projectId?

    projectPromise =
        if projectId?
            req.db.master.jsonQuery """select customer_id, permissions from projects where id = $1""", projectId
        else
            Promise.resolve {}

    Promise.props
        user: req.db.master.jsonQuery """select permissions, customer_id from users_hq where id = $1""", req.session.data.userId
        project: projectPromise
    .then (result) ->
        {user, project} = result
        permissions = util.getHQPermissions projectId, project.permissions, user.permissions

        drawGeoms = req.route.path.match /\/geometry\//i

        if projectId? && (!(permissions.permittedProjects == "all" || R.contains(projectId.toString(), permissions.permittedProjects)) ||
            (permissions.permittedProjects == "all" && user.customerId != project.customerId))
                res.status(403).send "Project access denied"

        else if drawGeoms && !permissions.drawing
            res.status(403).send "Map drawing prohibited"
        else
            req.permissions = permissions
            req.customerId = project.customerId
            next()

exports.connectToDb = require "./reqconn"
exports.obtainSession = require "./session"
