test = require "./setup"
helpers = require "../routes/helpers"
project = require("../routes/v4/project")(helpers)

userData =
    beaconEvents: [
        { type: "entry", coord: 1476219013000 }
        { type: "exit",  coord: 1476220205000 }
        { type: "entry", coord: 1476221165000 }
        { type: "exit",  coord: 1476222125000 }
    ]

    positions: [
        { coord: 1476219314358 }
        { coord: 1476219414358 }
        { coord: 1476219614977 }
    ]

logs =
    messages: push: (msg) -> console.log msg

describe "Time to break", ->
    it "returns correct time for users with standard hours", ->
        params =
            signonAtUtc: 1476218549
            periodEndUtc: 1476269999
            userId: 894
            permissions: ["view_drone_imagery","view_overlays"]

        now = 1476220210  # After 1st break
        res = project._calcTimeToBreak now, params, params.permissions, userData
        assert.equal res.ttb, 1476218549 + (7.75 * 60 * 60) - now

    it "returns correct time for users with extended hours", ->
        params =
            signonAtUtc: 1476218549
            periodEndUtc: 1476269999
            userId: 894
            permissions: ["view_drone_imagery","view_overlays", "extended_hours"]

        now = 1476220210  # After 1st break
        res = project._calcTimeToBreak now, params, params.permissions, userData
        assert.equal res.ttb, 1476220205 + (6.75 * 60 * 60) - now

