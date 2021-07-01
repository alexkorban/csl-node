global.ENV = "test"

global.assert = require("chai").assert
global.jsc = require "jsverify"
global.moment = require "moment-timezone"
global.R = require "ramda"
global.Series = require "../models/series"
global.util = require "../util"

module.exports =
    enum: (values) ->
        jsc.oneof R.map(jsc.constant, values)
#   Could also be implemented via jsc.integer like this:
#        jsc.integer(0, values.length - 1).smap (index) ->
#            #console.log "Lookup on #{JSON.stringify values}"
#            values[index]
#        , (enumVal) ->
#            #console.log "Reverse lookup on #{JSON.stringify values}"
#            R.findIndex R.equals(enumVal), values

    interval: (valueType) ->
        jsc.pair(valueType, valueType).smap (val) ->
            start: {coord: Math.min(val[0], val[1])}, end: {coord: Math.max(val[0], val[1])}
        , (interval) ->
            [interval.start.coord, interval.end.coord]
