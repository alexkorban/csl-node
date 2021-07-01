if process.env.NODE_ENV != "dev"
    require "newrelic"

global.express = require "express"
global.R = require "ramda"
global.Promise = require "bluebird"
global.S = require "string"
global.pj = require "prettyjson"
global.bcrypt = Promise.promisifyAll require 'bcrypt'
global.moment = require "moment-timezone"

global.util = require "./util"

global.db = require "./models"
global.Series = require "./models/series"


http = require "http"
path = require "path"
connectTimeout = require "connect-timeout"
bodyParser = require "body-parser"
compression = require "compression"
errorHandler = require "errorhandler"
#morgan = require "morgan"


app = express()

#app.use morgan "combined"
app.use compression()
app.use bodyParser.json limit: "50mb"


# set a global timeout value
#app.get('/some/route', longTimeout, yourHandler); // or you can set per-route timeouts
app.use connectTimeout "120s"

# development only
app.use errorHandler() if process.env.NODE_ENV == "dev"

# setup routes
routes = require "./routes"
routes.attachTo app


# add "0.0.0.0" as the second argument in order to allow iOS Simulator to connect
server = app.listen process.env.PORT, =>
    host = server.address().address
    port = server.address().port
    console.log "SafeSiteNode listening on http://%s:%s", host, port
