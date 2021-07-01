rollback = (req, log, connName) ->
    if req.db[connName].isInTransaction
        req.db[connName].rollback().then ->
            log "Rolled back #{connName} DB transaction"
    else
        Promise.resolve()

onError = (req, res, httpCode, handler, error) ->
    log = (msg) ->
        if req.logs? then req.logs.messages.push msg else console.log msg

    log "Error processing request:"
    if req.logs?
        req.logs.error = error
        req.logs.handler = handler
    else
        log handler: handler, details: error

    Promise.all [rollback(req, log, "master"), rollback(req, log, "follower")]
    .then ->
        if req.logs?
            req.logs.responseCode = httpCode
            console.log if process.env.NODE_ENV == "dev"
                pj.render req.logs
            else
                JSON.stringify req.logs
        res.status(httpCode).send JSON.stringify(error)


exports.withErrorHandling = (routeHandler) ->
    (req, res) ->
        p = routeHandler req, res
        return if !p?

        p.then ->
            if req.logs? && !R.isEmpty req.logs.messages
                req.logs.responseCode = 200
                console.log if process.env.NODE_ENV == "dev"
                    pj.render req.logs
                else
                    JSON.stringify req.logs
            else
                # No logs - do nothing
        .catch TypeError, ReferenceError, (error) ->
            onError req, res, 500, "TypeError|ReferenceError", error
        .error (error) ->
            # catches Promise.RejectionError
            onError req, res, 500, "Promise.RejectionError", error
        .catch (error) ->
            onError req, res, 500, "Generic", error





