reportNames = [ "areas", "breaks", "concreteTests", "driverFitness", "lightVehicles", "loadCounts"
              , "projectVisits", "speedBands", "timeline"
              ]
queries = R.mergeAll R.map ((name) -> "#{name}": require "./reports/#{S(name).underscore().s}"), reportNames

module.exports = (helpers) ->
    getReports: helpers.withErrorHandling (req, res) ->
        Promise.resolve null
        .then ->
            reports = [
                { url: "timeline",      label: "Activity" }
                { url: "areas",         label: "Areas" }
                { url: "breaks",        label: "Chain of responsibility" }
                { url: "driverFitness", label: "Driver fitness" }
                { url: "lightVehicles", label: "Light vehicles" }
                { url: "speedBands",    label: "Movement" }
                { url: "projectVisits", label: "On-Site" }
            ]

            if req.permissions.loadCounts
                reports.push { url: "loadCounts", label: "Load counts" }

            if req.permissions.paving
                reports.push { url: "concreteTests", label: "Concrete tests" }

            sortedReports = R.sortBy R.prop("label"), reports

            permittedReports = R.filter (report) ->
                req.permissions.reports[report.url]
            , sortedReports
            
            res.json permittedReports


    getReport: helpers.withErrorHandling (req, res) ->
        #console.log "REPORT REQUEST START", moment().format "H:mm:ss"

        reportName = req.params.reportName

        if !req.permissions.reports[reportName]
            res.status(403).send "Report access denied"
            return

        getReportData = queries[reportName]

        if !getReportData?
            res.status(404).send "Report not found"
            return

        getReportData(req, res)
        .then (result) ->
            #console.log "REPORT REQUEST END", moment().format "H:mm:ss"
            res.json result



