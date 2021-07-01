debug = require('debug')('session')
uid = require "uid-safe"

module.exports = (req, res, next) ->
    debug "middleware: session"

    # connection already set up
    if req.session?
        debug "req.session already exists"
        return next()

    sessionId = req.header("SessionID") || req.query.sessionId || ""

    # proxy end() to end the transaction (if needed) and release the client
    origEnd = res.end
    res.end = (data, encoding) ->
        debug "wrapper res.end() called"
        res.end = origEnd  # restore the original handler

        if !req.session
            debug "no req.session, calling res.end()"
        else
            debug "saving session data, calling res.end()"

            q = if req.session.isNew
                """insert into sessions (id, data) values ($1, $2)"""
            else
                """update sessions set data = $2::json, updated_at = now() where id = $1"""

            req.db.master.query q, req.session.id, db.renameKeysForDb req.session.data
            .catch ->
                debug "could not save session #{req.session.id}"
            .finally ->
                delete req.session

        res.end(data, encoding)

    debug "loading session from the DB"

    q = """select id, data from sessions where id = $1"""

    req.db.master.jsonQuery q, sessionId
    .then (session) ->
        debug "session loaded: ", session
        if R.isEmpty session
            session =
                data: {}
                create: ->
                    req.session.id = uid.sync 18
                    req.session.isNew = true

        req.session = db.renameKeysForJson session
        req.logs.userId = req.session.data.userId ? null
        req.session
    .finally ->
        next()

