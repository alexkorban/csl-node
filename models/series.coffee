# Point = {coord}
# Interval = {start: Point, end: Point}  [start, end)
# SeriesPoint = Point + {type, ...}
# SeriesInterval = {interval: Interval, points: [SeriesPoint]}
# Series = [SeriesInterval]
# SeriesPointInterval = Interval<SeriesPoint>  (a point's type property can be null)

Interval =
    # Point | Interval -> Interval -> Bool
    contains: R.curry (containee, interval) ->
        if containee.coord?  # Point containee
            if interval.start.coord == interval.end.coord   # An improper interval is defined to contain its start
                containee.coord == interval.start.coord
            else
                containee.coord >= interval.start.coord && containee.coord < interval.end.coord
        else   # Interval containee
            containee.start.coord >= interval.start.coord && containee.end.coord <= interval.end.coord

    length: (interval) ->
        interval.end.coord - interval.start.coord


module.exports =
    Interval: Interval

    # seriesPoint has to be sorted in ascending order
    # domainIntervals have to be non-overlapping and sorted in ascending order
    # domainIntervals which don't contain any points will not be included in the series
    # points which don't fall into any domain interval will not be included in the series
    # [Interval] -> [SeriesPoint] -> Series
    makeSeries: R.curry (domainIntervals, seriesPoints) ->
        makeSeriesInterval = (domainInterval) ->
            interval: domainInterval
            points: R.filter ((p) -> Interval.contains(p, domainInterval)), seriesPoints
        R.reject ((si) -> R.isEmpty si.points), R.map(makeSeriesInterval, domainIntervals)


    # Series -> [SeriesPointInterval]
    getPointIntervals: (series) ->
        R.chain (seriesInterval) ->
            if R.isEmpty seriesInterval.points
                [{
                    start:
                        coord: seriesInterval.interval.start.coord
                        type: null
                    end:
                        coord: seriesInterval.interval.end.coord
                        type: null
                }]
            else if seriesInterval.points.length == 1
                singularPoint = seriesInterval.points[0]
                [{
                    start:
                        coord: seriesInterval.interval.start.coord
                        type: null
                    end: singularPoint
                }, {
                    start: singularPoint
                    end:
                        coord: seriesInterval.interval.end.coord
                        type: null
                }]
            else
                inner = R.map (pair) ->
                    start: pair[0]
                    end: pair[1]
                , R.aperture(2, seriesInterval.points)

                # Add extra intervals: interval start : first point & last point : interval end
                res = R.prepend
                    start:
                        coord: seriesInterval.interval.start.coord
                        type: null
                    end: inner[0].start
                , inner
                R.append
                    start: R.last(res).end
                    end:
                        coord: seriesInterval.interval.end.coord
                        type: null
                , res
        , series


    # Joins adjacent intervals according to the supplied predicate
    # (Interval -> Interval -> Bool) -> [Interval] -> [Interval]
    joinIntervals: R.curry (joinPredicate, inputIntervals) ->
        return inputIntervals if inputIntervals.length < 2

        # By construction, the last interval is never marked joinable
        # (this is important for the grouping function below)
        markJoinableIntervals = (intervals) ->
            intervalsSansLast = R.map (adjIntervalPair) ->
                interval: adjIntervalPair[0]
                isJoinable: joinPredicate adjIntervalPair...
            , R.aperture(2, intervals)

            R.append {interval: R.last(intervals), isJoinable: false}, intervalsSansLast

        join = (joinIntervals) ->
            start: joinIntervals[0].interval.start
            end: R.last(joinIntervals).interval.end

        combineJoinableIntervals = (markedIntervals) ->
            #console.log "markedIntervals = ", markedIntervals
            if R.isEmpty markedIntervals
                []
            else
                joinSegment = R.takeWhile R.prop("isJoinable"), markedIntervals
                joinSegment.push markedIntervals[joinSegment.length]
                #console.log "joinSegment: ", joinSegment

                R.concat [join joinSegment], combineJoinableIntervals(markedIntervals.slice joinSegment.length)

        R.pipe(markJoinableIntervals, combineJoinableIntervals) inputIntervals


    # Type -> Type -> [SeriesPoint] -> [SeriesPoint]
    # Input points have to be sorted by coord ascending
    squashOverlappingIntervals: R.curry (startType, endType, points) ->
        return points if points.length < 2

        incr = (type) -> if type == startType then 1 else -1

        # Annotate points with running total of start/end points and a running minimum of the running total
        # These values allow us to find the relevant points:
        # - start of a gap (not covered by any interval) is a point with negative runSum that is equal to min runSum
        #   across all points
        # - end of a gap is the point right after that
        pointsWithRunSum = R.scan (acc, p) ->
            {runSum: acc.runSum + incr(p.type), min: Math.min(acc.min, acc.runSum + incr(p.type)), point: p}
        , {runSum: 0, min: 0, point: undefined}, points

        min = R.last(pointsWithRunSum).min

        # This defines points where ALL intervals have ended
        isCompleteExit = (annotatedPoint) ->
            annotatedPoint.runSum <= 0 && annotatedPoint.runSum == min && annotatedPoint.point.type == endType

        squash = R.pipe R.aperture(2)
        , R.map((pair) ->       # Find entries and exits denoting regions with no overlapping intervals
            if isCompleteExit(pair[1]) ||                                # Exit out of all intervals
                (!pair[0].point? && pair[1].point.type == startType) ||  # Entry at the start of point sequence
                (pair[0].point? && isCompleteExit(pair[0]))              # Entry right after an exit out of all intervals
                    pair[1].point
            else
                null
        )
        , R.reject R.isNil

        squash pointsWithRunSum


    # [Interval] -> [Interval]
    # `intervals` have to be sorted by `.start.coord`
    # Prop: Returned intervals don't overlap
    # Prop: The start point of the first returned interval matches the start point of the first element of `intervals`
    # Prop: The end point of the last returned interval matches the max end point of `intervals`
    calcMinimalCoveringIntervals: (intervals) ->
        return intervals if intervals.length < 2

        recurse = (currInterval, overlappingIntervals, intervals) ->
            splitIntervals = R.splitWhen ((interval) -> interval.start.coord >= currInterval.end.coord), intervals

            # The number of overlapping intervals at any point is expected to be << the total number of intervals
            # (for our use case, <= 10), therefore it's ok to sort them (which is something like O(N * log N))
            newOverlappingIntervals = R.pipe(R.concat(overlappingIntervals)
                , R.filter(Interval.contains(currInterval.end))
                , R.sortBy(R.path(["end", "coord"]))) splitIntervals[0]

            subsequentIntervals = splitIntervals[1]

            if !R.isEmpty newOverlappingIntervals
                longestInterval = R.last(newOverlappingIntervals)

                R.concat [currInterval], recurse(
                    {start: currInterval.end, end: longestInterval.end}
                    , R.init(newOverlappingIntervals)
                    , subsequentIntervals)
            else  # It's a gap which isn't covered by any interval => continue from the next closest interval
                if !R.isEmpty subsequentIntervals
                    R.concat [currInterval], recurse(
                        R.head(subsequentIntervals)
                        , []
                        , R.tail(subsequentIntervals)
                    )
                else  # Reached the end of the interval sequence
                    [currInterval]

        recurse R.head(intervals), [], R.tail(intervals)


