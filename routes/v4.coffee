module.exports = (mware, handlers) ->

    router = express.Router mergeParams: true
    middleware = [mware.obtainSession, mware.checkAuth, mware.authorise]

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    userRouter = express.Router mergeParams: true
    # shared token auth only - endpoints for mobile client
    userRouter.post "/sync", handlers.user.sync
    userRouter.post "/error", handlers.user.logError
    userRouter.post "/s3sign", handlers.user.s3sign

    userRouter.post "/:projectId/:id/permissions/create", middleware, handlers.user.permissions.createPermission
    userRouter.post "/:projectId/:id/permissions/delete", middleware, handlers.user.permissions.deletePermission

    userRouter.get "/", [mware.obtainSession, mware.checkAuth], handlers.user.getAll

    router.use "/users", userRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    userHqRouter = express.Router mergeParams: true
    userHqRouter.post "/login", [mware.obtainSession], handlers.userHq.login
    userHqRouter.post "/logout", [mware.obtainSession], handlers.userHq.logout
    userHqRouter.post "/update", handlers.userHq.update  # special case, auth via admin token
    # login/password auth
    userHqRouter.get "/:projectId/users", middleware, handlers.userHq.getUsers
    userHqRouter.get "/:projectId/permissions", middleware, handlers.userHq.getPermissions
    userHqRouter.post "/:projectId/create", middleware, handlers.userHq.create  # special case, auth via admin token

    router.use "/users-hq", userHqRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    projectRouter = express.Router mergeParams: true

    projectRouter.get "/", middleware, handlers.project.getAll
    #projectRouter.post "/", middleware, handlers.project.create
    #projectRouter.put "/:id", middleware, handlers.project.update

    # mostly static data
    projectRouter.get "/:projectId/data/areas", middleware, handlers.project.data.getAreas
    projectRouter.get "/:projectId/data/assets", middleware, handlers.project.data.getAssets
    projectRouter.get "/:projectId/data/base-layers", middleware, handlers.project.data.getBaseLayers
    projectRouter.get "/:projectId/data/overlays", middleware, handlers.project.data.getOverlays
    projectRouter.get "/:projectId/data/roles", middleware, handlers.project.data.getRoles
    projectRouter.get "/:projectId/data/pavingUsers", middleware, handlers.project.data.getPavingUsers
    projectRouter.get "/:projectId/data/users", middleware, handlers.project.data.getUsers
    projectRouter.get "/:projectId/data/userAppConfigs", middleware, handlers.project.data.getUserAppConfigs

    # easel
    projectRouter.post "/:projectId/data/geometry/save", middleware, handlers.project.data.saveGeometry
    projectRouter.get  "/:projectId/data/geometry/delete/:geometryId", middleware, handlers.project.data.deleteGeometry

    # people & positions
    projectRouter.get "/:projectId/positions", middleware, handlers.project.positions.get
    projectRouter.get "/:projectId/positions/timeline", middleware, handlers.project.positions.getPositionTimeline

    # timeline
    projectRouter.get "/:projectId/timeline", middleware, handlers.project.timeline.get

    # Special case, auth via admin token
    projectRouter.post "/:projectId/create-permissions", handlers.project.createPermissions

    # notifications
    projectRouter.get "/:projectId/notifications", middleware, handlers.project.notifications.getAll
    projectRouter.get "/:projectId/notifications/get/:notificationId", middleware, handlers.project.notifications.getNotification
    projectRouter.post "/:projectId/notifications/create", middleware, handlers.project.notifications.create
    projectRouter.post "/:projectId/notifications/:notificationId/update", middleware, handlers.project.notifications.update
    projectRouter.post "/:projectId/notifications/:notificationId/delete", middleware, handlers.project.notifications.delete
    projectRouter.post "/:projectId/notifications/:notificationId/status/:action", middleware, handlers.project.notifications.updateStatus
    projectRouter.post "/:projectId/notifications/:notificationId/role/update", middleware, handlers.project.notifications.updateRole
    projectRouter.get "/:projectId/notifications/recipients", middleware, handlers.project.notifications.getRecipients
    projectRouter.post "/:projectId/notifications/recipients/create", middleware, handlers.project.notifications.createRecipient


    # login/password auth
    router.use "/projects", projectRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    pavingRouter = express.Router mergeParams: true

    pavingRouter.get "/:projectId/trucks", middleware, handlers.paving.getTruckInfo
    pavingRouter.get "/:projectId/batch-plants", middleware, handlers.paving.getBatchPlantInfo
    pavingRouter.get "/:projectId/slump", middleware, handlers.paving.getSlump
    pavingRouter.get "/:projectId/production", middleware, handlers.paving.getProduction
    pavingRouter.get "/:projectId/pavers", middleware, handlers.paving.getPaverInfo

    # login/password auth
    router.use "/paving", pavingRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    reportRouter = express.Router mergeParams: true

    reportRouter.get "/:projectId", middleware, handlers.reports.getReports
    reportRouter.get "/:projectId/:reportName", middleware, handlers.reports.getReport

    # login/password auth
    router.use "/reports", reportRouter

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    weatherRouter = express.Router mergeParams: true

    weatherRouter.post "/", handlers.weather.saveWeather
    weatherRouter.get "/:projectId", handlers.weather.getWeather

    router.use "/weather", weatherRouter

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    internalRouter = express.Router mergeParams: true

    internalRouter.post "/geoJsonQueries", middleware, handlers.internal.geoJsonQueries

    router.use "/internal", internalRouter

    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    #
    # These routes are for debugging / testing purposes. Not for use on production!
    #

    if process.env.NODE_ENV == "dev"
        developmentRouter = express.Router mergeParams: true

        developmentRouter.all  "/test", mware.setupLogs, handlers.development.test
        developmentRouter.post "/generate-positions", mware.setupLogs, handlers.development.genPositions

        router.use "/dev", developmentRouter


    #~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    router
