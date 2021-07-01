exports.pg = require("pg").native

Hashids = require "hashids"
uid = require "uid-safe"


camelize = (s) ->
    return s if s.indexOf("_") == -1

    s.replace /(\-|_|\s)+(.)?/g, (match, sep, c) ->
        if c then c.toUpperCase() else ""


underscorize = (s) ->
    s.replace /[A-Z]/g, (match) ->
        "_" + match.toLowerCase()


renameKeys = (o, renameFunc) ->
    return o if !o? || !R.is Object, o

    if R.isArrayLike o
        return (renameKeys(row, renameFunc) for row in o)

    build = {}
    for key, value of o
        # Get the destination key
        destKey = renameFunc key

        # If this is an object, recurse
        value = renameKeys(value, renameFunc) if typeof value is "object"

        # Set it on the result using the destination key
        build[destKey] = value

    build


exports.renameKeysForJson = (o) ->
    renameKeys o, camelize


exports.renameKeysForDb = (o) ->
    renameKeys o, underscorize


exports.generateCid = ->
    new Hashids(uid.sync(10)).encode(Math.floor new Date().getTime() / 10000)