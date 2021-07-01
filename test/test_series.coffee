test = require "./setup"
Series = require "../models/series"

# Interval = {start, end}  [start, end)
# SeriesPoint = {<pointCoord>, ...}
# SeriesInterval = {interval: Interval, points: [SeriesPoint]}
# Series = [coordKey: String, typeKey: String, intervals: [SeriesInterval]]
# SeriesPointInterval = {interval: Interval, startType: Type | Null, endType: Type | Null}


TSeriesPoint = jsc.record coord: jsc.integer, type: jsc.string
TInterval = test.interval jsc.integer
TIntervals = jsc.nearray TInterval
#TNIIntervals = ???

TSeriesInterval = jsc.record
    interval: TInterval
    points: jsc.nearray TSeriesPoint

TSeries = jsc.nearray TSeriesInterval

#TSeriesPointInterval:

describe "Interval", ->

    jsc.property "contains its start", TInterval, (interval) ->
        Series.Interval.contains({coord: interval.start.coord}, interval)


    jsc.property "doesn't contain its end", TInterval, (interval) ->
        if interval.start.coord == interval.end.coord
            true  # An improper interval is defined to contain its start point
        else
            !Series.Interval.contains({coord: interval.end.coord}, interval)


    jsc.property "detects point containment", TInterval, (interval) ->
        return true if interval.start.coord == interval.end.coord  # This property isn't applicable
                                                                   # to improper intervals

        pIn = jsc.integer(interval.start.coord, interval.end.coord - 1).generator()
        pOut1 = jsc.integer(interval.end.coord, interval.end.coord + 10).generator()
        pOut2 = jsc.integer(interval.start.coord - 11, interval.start.coord - 1).generator()

        #console.log interval, pIn, pOut1, pOut2

        (Series.Interval.contains({coord: pIn}, interval) &&
            !Series.Interval.contains({coord: pOut1}, interval) &&
            !Series.Interval.contains({coord: pOut2}, interval))


    jsc.property "contains itself", TInterval, (interval) ->
        Series.Interval.contains interval, interval


    jsc.property "detects interval containment", TInterval, (interval) ->
        return true if interval.start.coord == interval.end.coord  # This property isn't applicable
                                                                   # to improper intervals

        pIn = jsc.integer(interval.start.coord, interval.end.coord - 1).generator()
        pOut1 = jsc.integer(interval.end.coord + 1, interval.end.coord + 10).generator()  # Beyond the end
        pOut2 = jsc.integer(interval.start.coord - 11, interval.start.coord - 1).generator()  # Before the start

        #console.log interval, pIn, pOut1, pOut2

        (Series.Interval.contains({start: {coord: pIn}, end: {coord: pIn + 1}}, interval) &&
            !Series.Interval.contains({start: {coord: pIn}, end: {coord: pOut1}}, interval) &&
            !Series.Interval.contains({start: {coord: pOut2}, end: {coord: pIn}}, interval))


describe "Series", ->

    jsc.property "makeSeries returns valid series", (jsc.array TInterval), (jsc.array TSeriesPoint), (intervals, points) ->
        series = Series.makeSeries(intervals, points)
        R.is(Array, series) && R.all ((i) -> i.interval? && i.points?.length > 0), series


    describe "getPointIntervals", ->
        jsc.property "getPointIntervals returns total(points) + length(intervals)", TSeries, (series) ->
            Series.getPointIntervals(series).length == series.length + R.sum R.map ((i) -> i.points.length), series

        jsc.property "getPointIntervals produces correct numbers of boundary intervals", TSeries, (series) ->
            pIntervals = Series.getPointIntervals(series)

            R.filter(((i) -> !i.start.type?), pIntervals).length == series.length &&
                R.filter(((i) -> !i.end.type?), pIntervals).length == series.length


    describe "joinPointIntervals", ->
        jsc.property "interval count doesn't increase", TSeries, (series) ->
            #randomBool = -> Math.round(Math.random()) > 0
            pIntervals = Series.getPointIntervals(series)
            Series.joinIntervals(((x) -> true), pIntervals).length == 1 &&
                Series.joinIntervals(((x) -> false), pIntervals).length == pIntervals.length &&
                Series.joinIntervals(jsc.bool.generator, pIntervals).length <= pIntervals.length


    describe "squashOverlappingIntervals", ->

        jsc.property "point count doesn't increase and point order is preserved", (jsc.array TSeriesPoint), (rawPoints) ->
            points = R.map ((p) -> R.merge p, type: if jsc.bool.generator() then "e" else "x")
                , R.sortBy(R.prop("coord"), rawPoints)
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)
            squashedPoints.length <= points.length && R.equals(squashedPoints, R.sortBy(R.prop("coord"), squashedPoints))


        jsc.property "non-overlapping intervals are unchanged", (jsc.array TSeriesPoint), (rawPoints) ->
            initialBool = jsc.bool.generator()
            points = R.map ((p) -> initialBool = !initialBool; R.merge p, type: if initialBool then "e" else "x")
                , R.sortBy(R.prop("coord"), rawPoints)
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)

            pointsEq = (pair) -> pair[0].type == pair[1].type && pair[0]
            squashedPoints.length == points.length && R.all(((p) -> R.equals(p[0], p[1])), R.zip(points, squashedPoints))


        jsc.property "full overlaps are squashed down to one interval", (jsc.nearray TSeriesPoint), (rawPoints) ->
            rawPoints = R.sortBy R.prop("coord"), rawPoints

            setType = R.curry (type, p) -> R.merge p, type: type
            points = R.concat (R.map setType("e"), rawPoints), (R.map setType("x"), rawPoints)
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)
            res1 = squashedPoints.length == 2 && squashedPoints[0].type == "e" && squashedPoints[1].type == "x"

            points = R.concat (R.map setType("x"), rawPoints), (R.map setType("e"), rawPoints)
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)
            res2 = squashedPoints.length == 2 && squashedPoints[0].type == "x" && squashedPoints[1].type == "e"

            points = R.map setType("e"), rawPoints
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)
            res3 = squashedPoints.length == 1 && squashedPoints[0].type == "e"

            points = R.map setType("x"), rawPoints
            squashedPoints = Series.squashOverlappingIntervals("e", "x", points)
            res4 = squashedPoints.length == 1 && squashedPoints[0].type == "x"

            res1 && res2 && res3 && res4


    describe "calcMinimalCoveringIntervals", ->
        it "handles no overlaps", ->
            intervals =
                [ {start: {coord: 1}, end: {coord: 5}}
                , {start: {coord: 5}, end: {coord: 10}}
                , {start: {coord: 11}, end: {coord: 15}}
                ]

            res = Series.calcMinimalCoveringIntervals(intervals)
            assert.deepEqual intervals, res


        it "handles simple overlaps", ->
            intervals =
                [ {start: {coord: 1}, end: {coord: 5}}
                , {start: {coord: 4}, end: {coord: 10}}
                , {start: {coord: 9}, end: {coord: 15}}
                ]

            res = Series.calcMinimalCoveringIntervals(intervals)
            assert.deepEqual [
                { start: { coord: 1 }, end: { coord: 5 } },
                { start: { coord: 5 }, end: { coord: 10 } },
                { start: { coord: 10 }, end: { coord: 15 } } ]
            , res


        it "handles multiple overlaps", ->
            intervals =
                [ {start: {coord: 1}, end: {coord: 10}}
                , {start: {coord: 2}, end: {coord: 14}}
                , {start: {coord: 3}, end: {coord: 8}}
                , {start: {coord: 9}, end: {coord: 18}}
                , {start: {coord: 12}, end: {coord: 20}}
                , {start: {coord: 16}, end: {coord: 22}}
                , {start: {coord: 24}, end: {coord: 30}}
                ]

            res = Series.calcMinimalCoveringIntervals(intervals)

            assert.deepEqual [ { start: { coord: 1 }, end: { coord: 10 } },
                { start: { coord: 10 }, end: { coord: 18 } },
                { start: { coord: 18 }, end: { coord: 22 } },
                { start: { coord: 24 }, end: { coord: 30 } } ]
            , res


        jsc.property "it doesn't take more intervals than there are in the input", (jsc.array TInterval), (intervals) ->
            intervals = R.sortBy R.path(["start", "coord"]), intervals
            Series.calcMinimalCoveringIntervals(intervals).length <= intervals.length


        jsc.property "returned intervals do not overlap", (jsc.array TInterval), (intervals) ->
            intervals = R.sortBy R.path(["start", "coord"]), intervals
            res = Series.calcMinimalCoveringIntervals(intervals)

            R.all (intervalPair) ->
                intervalPair[0].end.coord <= intervalPair[1].start.coord
            , R.aperture(2, res)


        jsc.property "start and end points of input and output match", (jsc.nearray TInterval), (intervals) ->
            intervals = R.sortBy R.path(["start", "coord"]), intervals
            res = Series.calcMinimalCoveringIntervals(intervals)
            maxEndPoint = R.reduce(R.maxBy(R.path(["end", "coord"])), {end: coord: -Infinity}, intervals).end
            res[0].start.coord == intervals[0].start.coord && R.last(res).end.coord == maxEndPoint.coord