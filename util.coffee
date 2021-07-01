abbrevArrays = (val) ->
    if !val? || typeof val != 'object'
        return val
    if R.isArrayLike val
        #console.log "treating val as array"
        if val.length < 6
            return R.map ((item) -> abbrevArrays item), val
        else
            return ["#{val.length} items"]
    else
        #console.log "treating val as obj"
        R.map ((item) -> abbrevArrays item), val

exports.abbrevArrays = abbrevArrays

# Psi combinator (`on` in Haskell), except with function arguments reversed because otherwise they don't
# read well in prefix form
exports.on = R.curry (g, f, x, y) -> f g(x), g(y)  # f(g(x))(g(y))


exports.getHQPermissions = (projectId, projectPermissions, userPermissions) ->
    permittedProjects = if R.has "all", userPermissions
        "all"
    else
        R.keys userPermissions

    if projectId?
        reports = R.merge projectPermissions.reports, userPermissions[projectId]?.reports
        R.mergeAll [ projectPermissions, userPermissions[projectId], permittedProjects: permittedProjects, reports: reports ]
    else
        permittedProjects: permittedProjects


exports.takePipeSample = R.curry (name, shouldTakeSample, debugDataObj, pipeState) ->
    #logs?.messages.push "got to #{name}"
    if shouldTakeSample
        debugDataObj[name] = pipeState
    else
        # Do nothing
        pipeState


exports.logPipeState = R.curry (label, pipeState) ->
    console.log "#{label} = #{JSON.stringify pipeState}"
    pipeState
