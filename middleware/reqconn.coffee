debug = require("debug")("reqconn")

connectToDb = (databaseUrl, connName, req, res, next) ->
    debug "middleware: reqconn"

    req.db ?= {}

    # Connection already set up
    if req.db[connName]?
        debug "req.db.#{connName} already exists"
        return next()

    # Proxy end() to end the transaction (if needed) and release the client
    origEnd = res.end
    res.end = (data, encoding) ->
        debug "#{connName} wrapper for res.end() called"
        res.end = origEnd  # restore the original handler

        if !req.db[connName]?
            debug "no req.db.#{connName}, calling res.end()"
        else
            debug "releasing #{connName} connection, calling res.end()"
            req.db[connName].done()
            delete req.db[connName]

        res.end(data, encoding)


    # Get a connection to the db
    debug "getting new PG connection"
    db.pg.connect databaseUrl, (err, client, done) ->
        if err?
            debug "error getting new connection"
            return next(err)
        debug "got connection"

        # Create the connection object and add it to the request object
        dbConn =
            client: client
            done: done
            isInTransaction: false

            begin: Promise.method ->
                throw new Error "DB transaction already started" if @isInTransaction

                @query("begin").then =>
                    @isInTransaction = true


            commit: ->
                throw new Error "Not in DB transaction" if !@isInTransaction
                @query("commit").then =>
                    @isInTransaction = false


            rollback: ->
                throw new Error "Not in DB transaction" if !@isInTransaction
                @query("rollback").then =>
                    @isInTransaction = false


            # async
            query: (sql, args...) ->
                new Promise (resolve, reject) =>
                    q = @client.query sql, args, (err, result) ->
                        if err
                            reject R.mergeAll [ {message: err.toString(), query: q.text, params: q.values},
                                R.pick(['severity', 'position'], err), {stack: err.stack} ]

                            return

                        if result?
                            result.rows = db.renameKeysForJson result.rows
                        resolve result

            # async
            jsonArrayQuery: (sql, args...) ->
                q = """
                    select json_agg(r) as json
                    from (#{sql}) r
                    """
                @query(q, args...).then (result) ->
                    result?.rows?[0]?.json || []


            # async
            jsonQuery: (sql, args...) ->
                @jsonArrayQuery(sql, args...).then (result) ->
                    result?[0] || {}


        req.db[connName] = dbConn

        next()


module.exports = (req, res, next) ->
    connectToDb process.env.DATABASE_URL, "master", req, res, ->
        connectToDb process.env[process.env.DATABASE_FOLLOWER_VAR ? "DATABASE_URL"], "follower", req, res, next
