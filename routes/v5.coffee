module.exports = (mware, handlers) ->

    router = express.Router mergeParams: true
    middleware = [mware.obtainSession, mware.checkAuth, mware.authorise]

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    userRouter = express.Router mergeParams: true
    # shared token auth only - endpoints for mobile client
    userRouter.post "/sync", handlers.users.sync
    userRouter.post "/error", handlers.users.logError
    userRouter.post "/s3sign", handlers.users.s3sign

    userRouter.post "/:projectId/:id/permissions/create", middleware, handlers.users.permissions.createPermission
    userRouter.post "/:projectId/:id/permissions/delete", middleware, handlers.users.permissions.deletePermission

    userRouter.post "/:projectId/:id/notifications", middleware, handlers.users.notifications

    userRouter.get "/", [mware.obtainSession, mware.checkAuth], handlers.users.getAll

    router.use "/users", userRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    userHqRouter = express.Router mergeParams: true
    userHqRouter.post "/login", [mware.obtainSession], handlers.usersHq.login
    userHqRouter.post "/logout", [mware.obtainSession], handlers.usersHq.logout
    userHqRouter.post "/update", handlers.usersHq.update  # special case, auth via admin token
    # login/password auth
    userHqRouter.get "/:projectId/users", middleware, handlers.usersHq.getUsers
    userHqRouter.get "/:projectId/permissions", middleware, handlers.usersHq.getPermissions
    userHqRouter.post "/:projectId/create", middleware, handlers.usersHq.create  # special case, auth via admin token

    router.use "/users-hq", userHqRouter

    # ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

    projectRouter = express.Router mergeParams: true

    projectRouter.get "/", middleware, handlers.projects.getAll
    #projectRouter.post "/", middleware, handlers.projects.create
    #projectRouter.put "/:id", middleware, handlers.projects.update

    # data
    projectRouter.get "/:projectId/data/areas", middleware, handlers.projects.data.getAreas
    projectRouter.get "/:projectId/data/assets", middleware, handlers.projects.data.getAssets

    #geometries
    projectRouter.get "/:projectId/geometries/base-layers", middleware, handlers.projects.geometries.getBaseLayers
    projectRouter.get "/:projectId/geometries/overlays", middleware, handlers.projects.geometries.getOverlays

    # easel
    projectRouter.post "/:projectId/geometries/save", middleware, handlers.projects.geometries.saveGeometry
    projectRouter.get  "/:projectId/geometries/delete/:geometryId", middleware, handlers.projects.geometries.deleteGeometry

    # users
    projectRouter.get "/:projectId/users", middleware, handlers.projects.users.getUsers
    projectRouter.get "/:projectId/users/roles", middleware, handlers.projects.users.getRoles
    projectRouter.get "/:projectId/users/paving", middleware, handlers.projects.users.getPavingUsers
    projectRouter.get "/:projectId/users/app-configs", middleware, handlers.projects.users.getUserAppConfigs
    projectRouter.get "/:projectId/users/positions", middleware, handlers.projects.users.getPositions

    # vehicles
    projectRouter.get "/:projectId/vehicles", middleware, handlers.projects.vehicles.getVehicles
    projectRouter.get "/:projectId/vehicles/positions", middleware, handlers.projects.vehicles.getPositions
    projectRouter.get "/:projectId/vehicles/roles", middleware, handlers.projects.vehicles.getVehicleRoles

    # timeline
    projectRouter.get "/:projectId/timeline", middleware, handlers.projects.timeline.get
    projectRouter.get "/:projectId/timeline/positions", middleware, handlers.projects.timeline.getPositionTimeline

    # Special case, auth via admin token
    projectRouter.post "/:projectId/create-permissions", handlers.projects.createPermissions

    # notifications
    projectRouter.get "/:projectId/notifications", middleware, handlers.projects.notifications.getAll
    projectRouter.get "/:projectId/notifications/get/:notificationId", middleware, handlers.projects.notifications.getNotification
    projectRouter.post "/:projectId/notifications/create", middleware, handlers.projects.notifications.create
    projectRouter.post "/:projectId/notifications/:notificationId/update", middleware, handlers.projects.notifications.update
    projectRouter.post "/:projectId/notifications/:notificationId/delete", middleware, handlers.projects.notifications.delete
    projectRouter.post "/:projectId/notifications/:notificationId/status/:action", middleware, handlers.projects.notifications.updateStatus
    projectRouter.post "/:projectId/notifications/:notificationId/role/update", middleware, handlers.projects.notifications.updateRole
    projectRouter.get "/:projectId/notifications/recipients", middleware, handlers.projects.notifications.getRecipients
    projectRouter.post "/:projectId/notifications/recipients/create", middleware, handlers.projects.notifications.createRecipient


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
