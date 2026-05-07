Database = {}

local function dbResource()
    return Config.Database.Resource or Config.Database.Driver or 'oxmysql'
end

local lastDatabaseWarning = 0

local function warnDatabase(message)
    local now = os.time()
    if now - lastDatabaseWarning >= 15 then
        print(('[ssrp_business] %s'):format(message))
        lastDatabaseWarning = now
    end
end

local function waitForDatabase()
    if Config.Database.Driver ~= 'oxmysql' then
        warnDatabase(('Unsupported database driver "%s". Configure server/database.lua for your driver.'):format(tostring(Config.Database.Driver)))
        return false
    end

    local resource = dbResource()
    local waitMs = tonumber(Config.Database.WaitForStartMs) or 30000
    local deadline = os.time() + math.max(0, math.ceil(waitMs / 1000))
    local state = GetResourceState(resource)

    while state ~= 'started' do
        if waitMs <= 0 or os.time() >= deadline then
            warnDatabase(('Database resource "%s" is "%s", not "started". Ensure oxmysql before this resource and check oxmysql connection logs.'):format(resource, state))
            return false
        end

        Wait(250)
        state = GetResourceState(resource)
    end

    if not exports[resource] then
        warnDatabase(('Database resource "%s" is started but exports are unavailable. Check oxmysql installation.'):format(resource))
        return false
    end

    return true
end

local function safeCall(exportName, fallback, sql, params, cb)
    cb = cb or function() end
    if not waitForDatabase() then
        cb(fallback)
        return
    end

    local resource = dbResource()
    local ok, err = pcall(function()
        if exportName == 'query' then
            exports[resource]:query(sql, params, cb)
        elseif exportName == 'insert' then
            exports[resource]:insert(sql, params, cb)
        elseif exportName == 'update' then
            exports[resource]:update(sql, params, cb)
        else
            error(('Unsupported oxmysql export "%s"'):format(tostring(exportName)))
        end
    end)

    if not ok then
        print(('[ssrp_business] oxmysql %s failed: %s'):format(exportName, tostring(err)))
        cb(fallback)
    end
end

function Database.query(sql, params, cb)
    cb = cb or function() end
    safeCall('query', {}, sql, params or {}, function(result)
        cb(result or {})
    end)
end

function Database.single(sql, params, cb)
    cb = cb or function() end
    Database.query(sql, params or {}, function(result)
        cb(result and result[1] or nil)
    end)
end

function Database.insert(sql, params, cb)
    cb = cb or function() end
    safeCall('insert', nil, sql, params or {}, function(result)
        cb(result)
    end)
end

function Database.update(sql, params, cb)
    cb = cb or function() end
    safeCall('update', 0, sql, params or {}, function(result)
        cb(result or 0)
    end)
end
