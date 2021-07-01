dbm = require "db-migrate"
R = require "ramda"

roleData = [
    # First one is the default catch all role
    {"name": "",               "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},

    # Normal roles as defined by the mobile app
    {"name": "Backhoe",        "properties": {"is_machine":true,  "does_paving":false, "does_signon":false}},
    {"name": "Community",      "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Concrete truck", "properties": {"is_machine":true,  "does_paving":true,  "does_signon":true}},
    {"name": "Engineer",       "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Environment",    "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Foreman",        "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Grader",         "properties": {"is_machine":true,  "does_paving":false, "does_signon":false}},
    {"name": "Paver",          "properties": {"is_machine":true,  "does_paving":true,  "does_signon":false}},
    {"name": "Safety",         "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Surveyor",       "properties": {"is_machine":false, "does_paving":false, "does_signon":false}},
    {"name": "Truck",          "properties": {"is_machine":true,  "does_paving":false, "does_signon":true}}
]

dataToSql = (roleData) ->
    R.reduce (acc, value) ->
        acc += "\nupdate roles set properties = '" + (JSON.stringify value.properties) + "' where name = '" + value.name + "';"
    ,
    "",
    roleData

exports.up = (db, callback) ->
    db.runSql (dataToSql roleData), callback

exports.down = (db, callback) ->
    # Remove the new does_signon property
    transformations = { properties: R.omit(['does_signon']) }
    roleData = R.map (item) ->
        R.evolve(transformations, item)
    , roleData

    db.runSql (dataToSql roleData), callback

