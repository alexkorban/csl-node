test = require "./setup"
loadCountHelpers = require("../routes/v5/reports/load_counts")._helpers

dataFile = require "./data/calcDayLoadCounts_894_01_Jan.json"

TStartPoint = jsc.record
    coord: jsc.integer
    type: jsc.constant "load_entry" #test.enum(["load_entry", "dump_entry"])
    areaId: jsc.constant "A" #test.enum(["A", "B"])

TEndPoint = jsc.record
    coord: jsc.integer
    type: jsc.constant "load_exit" #test.enum(["load_entry", "dump_entry"])
    areaId: jsc.constant "A" #test.enum(["A", "B"])

TInterval = jsc.record
    start: TStartPoint
    end: TEndPoint

describe "Load count report", ->
    it "calculates", ->
        logs =
            messages: push: (msg) -> console.log msg

        res = loadCountHelpers.calcDayLoadCounts R.merge(dataFile.driverDay, isSpecificDumpArea: false)
            , dataFile.data, dataFile.params, logs
#        console.log res.cycles
        assert R.is(Object, res), "returns a result object"

    it "adjusts overlaps on intervals", ->
        intervals = [
            {start: {coord: 1},  end: {coord: 10}}
            {start: {coord: 8},  end: {coord: 20}}
            {start: {coord: 16}, end: {coord: 30}}
            {start: {coord: 24}, end: {coord: 40}}
        ]

        res = loadCountHelpers.adjustIntervalsToOverlapMidpoints(intervals)

        console.log "adjusted: ", res

        expected = [
            {start: {coord: 1},  end: {coord: 9 }}
            {start: {coord: 10}, end: {coord: 18}}
            {start: {coord: 19}, end: {coord: 27}}
            {start: {coord: 28}, end: {coord: 40}}
        ]

        assert R.equals(res, expected), "overlaps removed"

    jsc.property "can normalise dumps", jsc.nearray(TInterval), (intervals) ->
        evolver = (interval) ->
            interval.end = R.evolve {
                coord: R.add(1)
                type: (type) -> if type == "load_entry" then "load_exit" else "dump_exit"
            }, interval.start
            interval

        intervals = R.map evolver, intervals
        #console.log "Intervals", intervals
        res = loadCountHelpers.normaliseDumpIntervals(false, intervals)
        #console.log "Norm intervals: ", res

        R.pipe(
            R.map((interval) -> if interval.start.type == "load_entry" then "L" else "D")
            , R.join("")
            , R.test /^(LD)*L{0,1}$/) res

        # whatever seq of L D goes in, the result is (LD)*L{0,1}


    jsc.property "equalBy", jsc.nearray(TInterval), (intervals) ->
        intervals2 = R.clone intervals
        intervals3 = R.clone intervals2
        intervals3[0].start.type = "ZZZ"

        res1 = loadCountHelpers.equalBy R.path(["start", "type"]), intervals, intervals2
        res2 = loadCountHelpers.equalBy R.path(["start", "type"]), intervals, intervals3
        res1 && !res2


    jsc.property "reduceToSingleDump always returns a single object", jsc.nearray(TInterval), (intervals) ->
        res = loadCountHelpers.reduceToSingleDump(intervals)
#        console.log "reduced intervals: ", res
        R.is Object, res


    jsc.property "recombineAperturePairs restores original array", jsc.nearray(TInterval), (intervals) ->
        return true if intervals.length < 2
        input = R.aperture(2, intervals)
        output = loadCountHelpers.recombineAperturePairs(input)
        R.equals output, intervals


    jsc.property "adjustIntervalsToOverlapMidpoints doesn't change interval count", jsc.nearray(TInterval), (intervals) ->
        output = loadCountHelpers.adjustIntervalsToOverlapMidpoints(intervals)
        #console.log "aITOM input:", intervals
        #console.log "aITOM output:", output

        output.length == intervals.length
