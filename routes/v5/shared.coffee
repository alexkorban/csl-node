calcScheduledBreaks = (activePeriodInterval, beaconEvents, positions) ->
    MIN_SCHEDULED_BREAK = 15 * 60 * 1000 # ms
    MAX_PROXIMITY_GAP = 3 * 60 * 1000 # ms

    # Calculate beacon proximity intervals
    beaconSeries = R.map R.evolve(points: Series.squashOverlappingIntervals("entry", "exit"))
    , Series.makeSeries [activePeriodInterval], beaconEvents

    #req.logs.messages.push "Beacon series: #{JSON.stringify beaconSeries}"

    # Use this to join beacon proximity intervals with a small gap
    joinOverSmallGaps = (left, right) ->
        right.start.coord - left.end.coord < MAX_PROXIMITY_GAP

    # Take beacon proximity intervals
    getBeaconProximityIntervals = R.filter (pInt) ->
        pInt.start.type == "entry" && pInt.end.type == "exit"

    calcBeaconIntervals =
        R.pipe Series.getPointIntervals, getBeaconProximityIntervals, Series.joinIntervals(joinOverSmallGaps)

    # The input intervals are filtered and joined to identify scheduled breaks
    beaconIntervals = calcBeaconIntervals beaconSeries
    #req.logs.messages.push "Beacon intervals: #{JSON.stringify beaconIntervals}"

    # Merge beacon and GPS data to improve scheduled break detection accuracy
    positionSeries = Series.makeSeries beaconIntervals, positions

    selectValidBreakIntervals = R.filter (seriesInt) ->
        positionTimeSpan = R.last(seriesInt.points).coord - seriesInt.points[0].coord
        Series.Interval.length(seriesInt.interval) >= MIN_SCHEDULED_BREAK &&
            positionTimeSpan >= 0.2 * (seriesInt.interval.end.coord - seriesInt.interval.start.coord) &&
            seriesInt.points.length > 2

    breaks: R.pipe(selectValidBreakIntervals, R.pluck("interval")) positionSeries
    beaconSeries: beaconSeries
    beaconIntervals: beaconIntervals


module.exports =
    calcScheduledBreaks: calcScheduledBreaks