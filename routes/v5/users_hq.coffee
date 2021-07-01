module.exports = (helpers) ->
    create: helpers.withErrorHandling (req, res) ->
        if req.permissions.hr
            user = req.db.master.jsonQuery """
                select * from users_hq where email = lower($1)
            """
            , req.body.email

            customer = req.db.master.jsonQuery """
                select customer_id as id from users_hq where id = $1
            """
            , req.session.data.userId

            defaultPermissions =  "#{req.params.projectId}": reports: {}

            Promise.props
                user: user
                customer: customer
            .then (result) ->
                if R.isEmpty result.user
                    bcrypt.hashAsync(req.body.password, 10)
                    .then (bcryptedPassword) ->
                        req.db.master.query """
                            insert into users_hq(email, password_hash, permissions, customer_id)
                            values (lower($1), $2, $3, $4::integer)
                        """
                        , req.body.email, bcryptedPassword, JSON.stringify(defaultPermissions), result.customer.id
                    .then ->
                        res.json {msg: "User has been successfully created."}
                else
                    if result.user.customerId == result.customer.id
                        permissions =
                            if R.has req.params.projectId, result.user.permissions
                                result.user.permissions
                            else
                                R.merge result.user.permissions, defaultPermissions

                        req.db.master.query """
                            update users_hq
                            set permissions = $2
                            where email = lower($1)
                        """
                        , req.body.email, permissions
                        .then ->
                            res.json {msg: "User has been added to the project."}
                    else
                        res.json {msg: "Could not create user. This email is already in use."}
        else
            Promise.resolve(null).then -> res.status(403).send "Access denied"


    update: helpers.withErrorHandling (req, res) ->
        if !req.body.cslToken? || req.body.cslToken != process.env.CSL_ADMIN_TOKEN
            res.sendStatus 403
            return

        bcrypt.hashAsync(req.body.password, 10)
        .then (bcryptedPassword) ->
            req.db.master.query """
                update users_hq set password_hash = $2, permissions = coalesce($3, permissions), customer_id = coalesce($4, customer_id)
                where email = lower($1)
            """
            , req.body.email, bcryptedPassword, (if req.body.permissions then JSON.stringify(req.body.permissions) else null)
            , req.body.customerId
        .then ->
            res.json {}


    login: helpers.withErrorHandling (req, res) ->
        req.db.master.jsonQuery """
            select users_hq.*, customers.properties->>'logo' as customer_logo,
            (select permissions from projects where id = $2) as project_permissions
            from users_hq
            join customers on customer_id = customers.id
            where lower(email) = lower($1)
        """
        , req.body.email, req.body.projectId || 0
        .then (user) ->
            if R.isEmpty user
                res.sendStatus 401
                return

            bcrypt.compareAsync(req.body.password, user.passwordHash)
            .then (doesMatch) ->
                if doesMatch
                    if R.isEmpty req.session.data
                        req.session.create()
                    req.session.data.isAuthenticated = true
                    req.session.data.userId = user.id
                    res.json {
                        sessionId: req.session.id
                        permissions: util.getHQPermissions(req.body.projectId, user.projectPermissions, user.permissions)
                        customerLogo: user.customerLogo
                    }
                else
                    res.sendStatus 401 # Unauthorised/unauthenticated
                                 # Use 403 for when a user requests a resource they aren't allowed access to


    logout: helpers.withErrorHandling (req, res) ->
        # use dummy promise to employ promise-based error handling
        Promise.resolve().then ->
            req.session.data.isAuthenticated = false
            res.json {}


    getUsers: helpers.withErrorHandling (req, res) ->
        projectId = req.params.projectId
        if req.permissions.hr
            req.db.master.jsonArrayQuery """
                select email, permissions, customer_id,
                    (select permissions->'reports' from projects where id = $2) as project_reports
                from users_hq
                where customer_id = (select customer_id from users_hq where id = $1)
                order by email
            """
            , req.session.data.userId, req.params.projectId
            .then (users) ->
                req.db.master.jsonArrayQuery """
                    select id, name from projects where customer_id = (select customer_id from users_hq where id = $1)
                """
                , req.session.data.userId
                .then (projects) ->
                    projects = R.fromPairs R.map (project) ->
                        R.values project
                    , projects
                    users = R.map (user) ->
                        projectNames =
                            if R.has "all", user.permissions
                                "All"
                            else
                                R.map (projectId) ->
                                    projects[projectId]
                                , R.keys user.permissions
                        reports = R.merge user.projectReports, user.permissions[projectId]?.reports

                        name: user.name
                        email: user.email
                        projects: projectNames
                        reports: reports
                    , users
                    res.json users
        else
            Promise.resolve(null).then -> res.status(403).send "Access denied"

    getPermissions: helpers.withErrorHandling (req, res) ->
        Promise.resolve(null).then -> res.json req.permissions
