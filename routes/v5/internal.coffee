module.exports = (helpers) ->
    # Warning: security risk
    # Executes SQL queries passed from the client as an object of {id: sql} pairs
    # This endpoint uses the follower database so it's limited to read only queries
    geoJsonQueries: helpers.withErrorHandling (req, res) ->
        console.log "Queries body:", req.body
        if !req.permissions.csl
            Promise.resolve(null).then -> res.status(403).send "Access denied"
        else
            R.pipe(R.reject(R.isEmpty), R.map((sql) -> req.db.follower.jsonArrayQuery sql), Promise.props)(req.body)
            .then (queryResults) ->
                # Returns an object consisting of {id: <GeoJson FeatureCollection object} pairs
                res.json R.map (singleQueryResult) ->
                    type: "FeatureCollection"
                    features: R.map (row) ->
                        type: "Feature"
                        properties: {}
                        geometry: R.values(row)[0]
                    , singleQueryResult
                , queryResults
