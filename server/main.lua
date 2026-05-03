local ActiveShiftsBySource = {}
local ActiveShiftsByDiscord = {}
local ActiveShiftsById = {}
local Handlers = {}

local function debugLog(message)
    if Config.Debug then
        print(('[ssrp_business] %s'):format(message))
    end
end

local function trim(value)
    return tostring(value or ''):match('^%s*(.-)%s*$')
end

local function sanitizeText(value, maxLength)
    value = trim(value)
    value = value:gsub('%c', ' ')
    value = value:gsub('[<>]', '')
    value = value:gsub('%s+', ' ')

    maxLength = maxLength or 80
    if #value > maxLength then
        value = value:sub(1, maxLength)
    end

    return value
end

local function normalizeDiscordId(value)
    value = trim(value)
    value = value:gsub('^discord:', '')
    value = value:gsub('[^%d]', '')
    return value
end

local function isValidDiscordId(value)
    value = normalizeDiscordId(value)
    return value:match('^%d+$') ~= nil and #value >= 15 and #value <= 25
end

local function getDiscordId(src)
    src = tonumber(src)
    if not src or src <= 0 or not GetPlayerName(src) then
        return nil
    end

    for _, identifier in ipairs(GetPlayerIdentifiers(src)) do
        if identifier:sub(1, 8) == 'discord:' then
            return identifier:sub(9)
        end
    end

    return nil
end

local function getPlayerDisplayName(src)
    return sanitizeText(GetPlayerName(src) or ('Player ' .. tostring(src)), 80)
end

local function getPlayerCharacterName(src)
    local candidate = nil
    local ok, player = pcall(function()
        return Player(src)
    end)

    if ok and player and player.state then
        local state = player.state
        candidate = state.charName or state.characterName or state.fullName or state.name

        if not candidate and state.firstName and state.lastName then
            candidate = ('%s %s'):format(state.firstName, state.lastName)
        end
    end

    return sanitizeText(candidate or GetPlayerName(src) or ('Player ' .. tostring(src)), 80)
end

local function actorLabel(src)
    if src == 0 then
        return 'console'
    end

    return ('%s (%s)'):format(getPlayerDisplayName(src), getDiscordId(src) or 'no-discord')
end

local function logAction(src, message)
    print(('[ssrp_business] %s: %s'):format(actorLabel(src), message))
end

local function notify(src, kind, message)
    if src and src > 0 then
        TriggerClientEvent('ssrp_business:client:notify', src, kind or 'info', message)
    end
end

local function respond(src, requestId, response)
    if not requestId then
        return
    end

    TriggerClientEvent('ssrp_business:client:nuiResponse', src, requestId, response or { ok = true })
end

local function isAdmin(src)
    if src == 0 then
        return true
    end

    for _, permission in ipairs(Config.Admin.AcePermissions or {}) do
        if IsPlayerAceAllowed(src, permission) then
            return true
        end
    end

    for _, roleId in ipairs(Config.Admin.DiscordRoleIds or {}) do
        local ok, allowed = pcall(Config.Admin.HasDiscordRole, src, roleId)
        if ok and allowed then
            return true
        end
    end

    return false
end

local function isAllowedBusinessType(value)
    value = sanitizeText(value, 60)
    if value == '' then
        return false
    end

    if not Config.BusinessTypes or #Config.BusinessTypes == 0 then
        return true
    end

    local lowered = value:lower()
    for _, businessType in ipairs(Config.BusinessTypes) do
        if lowered == tostring(businessType):lower() then
            return true
        end
    end

    return false
end

local function normalizeStatus(value, fallback)
    value = sanitizeText(value, 20):lower()
    if value == 'active' or value == 'archived' then
        return value
    end

    return fallback or 'active'
end

local function mapEmployee(row)
    return {
        id = tonumber(row.id),
        businessId = tonumber(row.business_id),
        discordId = row.discord_id,
        displayName = row.display_name,
        title = row.title or 'Employee',
        addedBy = row.added_by,
        addedAt = row.added_at,
        status = row.status or 'active'
    }
end

local function mapShift(row)
    return {
        id = tonumber(row.id),
        businessId = tonumber(row.business_id),
        discordId = row.discord_id,
        displayName = row.display_name,
        shiftStart = row.shift_start,
        shiftEnd = row.shift_end,
        totalMinutes = tonumber(row.total_minutes) or 0,
        afkMinutes = tonumber(row.afk_minutes) or 0,
        status = row.status or 'active'
    }
end

local function mapBusiness(row)
    return {
        id = tonumber(row.id),
        name = row.name,
        type = row.type,
        ownerDiscordId = row.owner_discord_id,
        ownerDisplayName = row.owner_display_name,
        createdBy = row.created_by,
        createdAt = row.created_at,
        status = row.status or 'active',
        isOwner = row.isOwner or false,
        employeeTitle = row.employee_title,
        employees = {},
        activeEmployees = {},
        recentShifts = {}
    }
end

local function currentAfkSeconds(shift)
    local seconds = shift.afkSeconds or 0
    if shift.afk and shift.afkStartedAt then
        seconds = seconds + math.max(0, os.time() - shift.afkStartedAt)
    end

    return seconds
end

local function shiftToPublic(shift)
    if not shift then
        return nil
    end

    return {
        shiftId = shift.shiftId,
        businessId = shift.businessId,
        businessName = shift.businessName,
        businessType = shift.businessType,
        discordId = shift.discordId,
        displayName = shift.displayName,
        startedAt = shift.startedAt,
        isAfk = shift.afk and true or false,
        afkMinutes = math.floor(currentAfkSeconds(shift) / 60),
        totalMinutes = shift.totalMinutes or math.max(0, math.floor((os.time() - shift.startedAt) / 60)),
        status = shift.afk and 'afk' or (shift.status or 'active')
    }
end

local function refreshOpenUis()
    TriggerClientEvent('ssrp_business:client:refreshOpenUi', -1)
end

local function emitShiftStarted(src, shift)
    local payload = shiftToPublic(shift)
    TriggerEvent(Config.Integration.ShiftStartedEvent, src, payload)
    TriggerClientEvent('ssrp_business:client:shiftState', src, true, payload)
    refreshOpenUis()
end

local function emitShiftEnded(src, shift)
    local payload = shiftToPublic(shift)
    TriggerEvent(Config.Integration.ShiftEndedEvent, src, payload)

    if src and src > 0 then
        TriggerClientEvent('ssrp_business:client:shiftState', src, false, nil)
    end

    refreshOpenUis()
end

local function emitAfkChanged(src, shift)
    local payload = shiftToPublic(shift)
    TriggerEvent(Config.Integration.ShiftAfkChangedEvent, src, payload)

    if src and src > 0 then
        TriggerClientEvent('ssrp_business:client:shiftState', src, true, payload)
    end

    refreshOpenUis()
end

local function getActiveShiftForSource(src)
    src = tonumber(src)
    if not src or src <= 0 then
        return nil
    end

    local shift = ActiveShiftsBySource[src]
    if shift then
        return shift
    end

    local discordId = getDiscordId(src)
    if discordId then
        return ActiveShiftsByDiscord[discordId]
    end

    return nil
end

local function resolveShift(playerOrDiscord)
    local possibleSource = tonumber(playerOrDiscord)
    if possibleSource and GetPlayerName(possibleSource) then
        local shift = getActiveShiftForSource(possibleSource)
        if shift then
            return shift
        end
    end

    return ActiveShiftsByDiscord[normalizeDiscordId(playerOrDiscord)]
end

local function getActiveEmployeesForBusiness(businessId)
    local employees = {}

    for _, shift in pairs(ActiveShiftsById) do
        if shift.businessId == businessId then
            employees[#employees + 1] = shiftToPublic(shift)
        end
    end

    table.sort(employees, function(left, right)
        return tostring(left.displayName):lower() < tostring(right.displayName):lower()
    end)

    return employees
end

local function fetchBusiness(businessId, cb)
    Database.single('SELECT * FROM businesses WHERE id = ? LIMIT 1', { businessId }, cb)
end

local function enrichBusinesses(rows, cb)
    local businesses = {}
    local historyLimit = tonumber(Config.Shifts.HistoryLimit) or 25
    if historyLimit < 1 then
        historyLimit = 1
    end

    local function step(index)
        if index > #rows then
            cb(businesses)
            return
        end

        local business = mapBusiness(rows[index])

        Database.query('SELECT id, business_id, discord_id, display_name, title, added_by, added_at, status FROM business_employees WHERE business_id = ? AND status = "active" ORDER BY display_name ASC', {
            business.id
        }, function(employeeRows)
            for _, employee in ipairs(employeeRows or {}) do
                business.employees[#business.employees + 1] = mapEmployee(employee)
            end

            business.activeEmployees = getActiveEmployeesForBusiness(business.id)

            Database.query(('SELECT id, business_id, discord_id, display_name, shift_start, shift_end, total_minutes, afk_minutes, status FROM business_shifts WHERE business_id = ? ORDER BY shift_start DESC LIMIT %d'):format(historyLimit), {
                business.id
            }, function(shiftRows)
                for _, shift in ipairs(shiftRows or {}) do
                    business.recentShifts[#business.recentShifts + 1] = mapShift(shift)
                end

                businesses[#businesses + 1] = business
                step(index + 1)
            end)
        end)
    end

    step(1)
end

local function onlinePlayers()
    local players = {}

    for _, playerId in ipairs(GetPlayers()) do
        local src = tonumber(playerId)
        players[#players + 1] = {
            source = src,
            discordId = getDiscordId(src) or '',
            displayName = getPlayerDisplayName(src),
            characterName = getPlayerCharacterName(src)
        }
    end

    table.sort(players, function(left, right)
        return tostring(left.displayName):lower() < tostring(right.displayName):lower()
    end)

    return players
end

local function buildDashboard(src, cb)
    local discordId = getDiscordId(src)
    if not discordId then
        cb(nil, 'Your Discord identifier was not found.')
        return
    end

    local byId = {}
    local ordered = {}

    local function addBusiness(row, isOwner, employeeTitle)
        local id = tonumber(row.id)
        if not byId[id] then
            row.isOwner = false
            row.employee_title = nil
            byId[id] = row
            ordered[#ordered + 1] = row
        end

        if isOwner then
            byId[id].isOwner = true
        end

        if employeeTitle then
            byId[id].employee_title = employeeTitle
        end
    end

    Database.query('SELECT * FROM businesses WHERE owner_discord_id = ? AND status = "active" ORDER BY name ASC', {
        discordId
    }, function(ownedRows)
        for _, row in ipairs(ownedRows or {}) do
            addBusiness(row, true, nil)
        end

        Database.query('SELECT b.*, e.title AS employee_title FROM businesses b INNER JOIN business_employees e ON e.business_id = b.id WHERE e.discord_id = ? AND e.status = "active" AND b.status = "active" ORDER BY b.name ASC', {
            discordId
        }, function(employeeRows)
            for _, row in ipairs(employeeRows or {}) do
                addBusiness(row, false, row.employee_title)
            end

            enrichBusinesses(ordered, function(businesses)
                cb({
                    player = {
                        source = src,
                        discordId = discordId,
                        displayName = getPlayerDisplayName(src),
                        characterName = getPlayerCharacterName(src)
                    },
                    businesses = businesses,
                    activeShift = shiftToPublic(getActiveShiftForSource(src))
                })
            end)
        end)
    end)
end

local function canStartShift(src, business, cb)
    local discordId = getDiscordId(src)
    if not discordId then
        cb(false, 'Discord identifier is required.')
        return
    end

    if business.owner_discord_id == discordId then
        cb(true, 'Owner')
        return
    end

    Database.single('SELECT id, title FROM business_employees WHERE business_id = ? AND discord_id = ? AND status = "active" LIMIT 1', {
        business.id,
        discordId
    }, function(employee)
        if employee then
            cb(true, employee.title or 'Employee')
        else
            cb(false, 'You are not on this business payroll.')
        end
    end)
end

local function ensureNoActiveShift(discordId, cb)
    if ActiveShiftsByDiscord[discordId] then
        cb(false, 'You already have an active business shift.')
        return
    end

    Database.single('SELECT id FROM business_shifts WHERE discord_id = ? AND shift_end IS NULL AND status IN ("active", "afk") LIMIT 1', {
        discordId
    }, function(existing)
        if existing then
            cb(false, 'You already have an active business shift.')
        else
            cb(true)
        end
    end)
end

local function removeActiveShift(shift)
    if not shift then
        return
    end

    if shift.source then
        ActiveShiftsBySource[shift.source] = nil
    end

    ActiveShiftsByDiscord[shift.discordId] = nil
    ActiveShiftsById[shift.shiftId] = nil
end

local function endActiveShift(src, status, cb)
    local shift = getActiveShiftForSource(src)
    cb = cb or function() end

    if not shift then
        cb(false, 'No active business shift found.')
        return
    end

    local now = os.time()
    local afkSeconds = currentAfkSeconds(shift)
    local totalMinutes = math.max(0, math.floor((now - shift.startedAt) / 60))
    local afkMinutes = math.max(0, math.floor(afkSeconds / 60))

    shift.afk = false
    shift.afkSeconds = afkSeconds
    shift.afkStartedAt = nil
    shift.status = status or 'ended'
    shift.totalMinutes = totalMinutes
    shift.afkMinutes = afkMinutes

    Database.update('UPDATE business_shifts SET shift_end = NOW(), total_minutes = ?, afk_minutes = ?, status = ?, is_afk = 0 WHERE id = ?', {
        totalMinutes,
        afkMinutes,
        shift.status,
        shift.shiftId
    }, function()
        removeActiveShift(shift)
        emitShiftEnded(src, shift)
        cb(true, 'Shift ended.')
    end)
end

local function setAfkState(src, isAfk)
    local shift = getActiveShiftForSource(src)
    if not shift then
        return
    end

    if isAfk and not shift.afk then
        shift.afk = true
        shift.afkStartedAt = os.time()
        shift.status = 'afk'

        Database.update('UPDATE business_shifts SET status = "afk", is_afk = 1 WHERE id = ?', {
            shift.shiftId
        }, function()
            debugLog(('Marked %s AFK for business shift %s.'):format(shift.discordId, shift.shiftId))
        end)

        emitAfkChanged(src, shift)
        return
    end

    if not isAfk and shift.afk then
        shift.afkSeconds = currentAfkSeconds(shift)
        shift.afk = false
        shift.afkStartedAt = nil
        shift.status = 'active'

        Database.update('UPDATE business_shifts SET status = "active", is_afk = 0, afk_minutes = ? WHERE id = ?', {
            math.floor((shift.afkSeconds or 0) / 60),
            shift.shiftId
        }, function()
            debugLog(('Marked %s active for business shift %s.'):format(shift.discordId, shift.shiftId))
        end)

        emitAfkChanged(src, shift)
    end
end

local function archiveBusinessSideEffects(businessId, reason)
    Database.update('UPDATE business_employees SET status = "archived" WHERE business_id = ? AND status = "active"', {
        businessId
    })

    local sources = {}
    for _, shift in pairs(ActiveShiftsById) do
        if shift.businessId == businessId then
            sources[#sources + 1] = shift.source
        end
    end

    for _, src in ipairs(sources) do
        endActiveShift(src, reason or 'ended_business_archived')
    end

    Database.update('UPDATE business_shifts SET shift_end = NOW(), total_minutes = TIMESTAMPDIFF(MINUTE, shift_start, NOW()), status = ?, is_afk = 0 WHERE business_id = ? AND shift_end IS NULL AND status IN ("active", "afk")', {
        reason or 'ended_business_archived',
        businessId
    })
end

local function assertAdmin(src, done)
    if not isAdmin(src) then
        done({ ok = false, message = 'You do not have business admin access.' })
        return false
    end

    return true
end

local function assertOwner(src, business, done)
    local discordId = getDiscordId(src)
    if not discordId or business.owner_discord_id ~= discordId then
        done({ ok = false, message = 'Only the business owner can do that.' })
        return false
    end

    return true
end

local function validateBusinessInput(payload)
    local name = sanitizeText(payload.name, 80)
    local businessType = sanitizeText(payload.type, 60)

    if name == '' then
        return nil, 'Business name is required.'
    end

    if not isAllowedBusinessType(businessType) then
        return nil, 'Business type is not allowed.'
    end

    return {
        name = name,
        type = businessType
    }
end

local function createBusinessWithOwner(src, input, ownerDiscordId, ownerDisplayName, done)
    local function insertBusiness()
        Database.insert('INSERT INTO businesses (name, type, owner_discord_id, owner_display_name, created_by, status) VALUES (?, ?, ?, ?, ?, "active")', {
            input.name,
            input.type,
            ownerDiscordId,
            ownerDisplayName,
            actorLabel(src)
        }, function(insertId)
            if not insertId then
                done({ ok = false, message = 'Database insert failed.' })
                return
            end

            logAction(src, ('created business "%s" for %s'):format(input.name, ownerDiscordId))
            refreshOpenUis()
            done({ ok = true, message = 'Business created.', id = insertId })
        end)
    end

    if Config.BusinessRules.AllowMultipleBusinessesPerOwner then
        insertBusiness()
        return
    end

    Database.single('SELECT id FROM businesses WHERE owner_discord_id = ? AND status = "active" LIMIT 1', {
        ownerDiscordId
    }, function(existing)
        if existing then
            done({ ok = false, message = 'That owner already has an active business.' })
        else
            insertBusiness()
        end
    end)
end

Handlers['business:getDashboard'] = function(src, _, done)
    buildDashboard(src, function(data, errorMessage)
        if not data then
            done({ ok = false, message = errorMessage or 'Unable to load business data.' })
            return
        end

        done({ ok = true, data = data })
    end)
end

Handlers['business:startShift'] = function(src, payload, done)
    local businessId = tonumber(payload.businessId)
    if not businessId then
        done({ ok = false, message = 'Business is required.' })
        return
    end

    local discordId = getDiscordId(src)
    if not discordId then
        done({ ok = false, message = 'Discord identifier is required.' })
        return
    end

    fetchBusiness(businessId, function(business)
        if not business or business.status ~= 'active' then
            done({ ok = false, message = 'Business was not found.' })
            return
        end

        canStartShift(src, business, function(allowed, reason)
            if not allowed then
                done({ ok = false, message = reason })
                return
            end

            ensureNoActiveShift(discordId, function(clear, message)
                if not clear then
                    done({ ok = false, message = message })
                    return
                end

                local displayName = getPlayerCharacterName(src)

                Database.insert('INSERT INTO business_shifts (business_id, discord_id, display_name, shift_start, afk_minutes, status, is_afk) VALUES (?, ?, ?, NOW(), 0, "active", 0)', {
                    businessId,
                    discordId,
                    displayName
                }, function(shiftId)
                    if not shiftId then
                        done({ ok = false, message = 'Could not start shift.' })
                        return
                    end

                    local shift = {
                        source = src,
                        shiftId = tonumber(shiftId),
                        businessId = businessId,
                        businessName = business.name,
                        businessType = business.type,
                        discordId = discordId,
                        displayName = displayName,
                        startedAt = os.time(),
                        afk = false,
                        afkStartedAt = nil,
                        afkSeconds = 0,
                        status = 'active'
                    }

                    ActiveShiftsBySource[src] = shift
                    ActiveShiftsByDiscord[discordId] = shift
                    ActiveShiftsById[shift.shiftId] = shift

                    emitShiftStarted(src, shift)
                    done({ ok = true, message = 'Shift started.', data = shiftToPublic(shift) })
                end)
            end)
        end)
    end)
end

Handlers['business:endShift'] = function(src, _, done)
    endActiveShift(src, 'ended', function(ok, message)
        done({ ok = ok, message = message })
    end)
end

Handlers['business:addEmployee'] = function(src, payload, done)
    local businessId = tonumber(payload.businessId)
    local discordId = normalizeDiscordId(payload.discordId)
    local displayName = sanitizeText(payload.displayName, 80)
    local title = sanitizeText(payload.title or 'Employee', 80)

    if not businessId then
        done({ ok = false, message = 'Business is required.' })
        return
    end

    if not isValidDiscordId(discordId) then
        done({ ok = false, message = 'Valid Discord ID is required.' })
        return
    end

    if displayName == '' then
        done({ ok = false, message = 'Display name is required.' })
        return
    end

    if title == '' then
        title = 'Employee'
    end

    fetchBusiness(businessId, function(business)
        if not business or business.status ~= 'active' then
            done({ ok = false, message = 'Business was not found.' })
            return
        end

        if not assertOwner(src, business, done) then
            return
        end

        if not Config.BusinessRules.AllowOwnerAsEmployee and business.owner_discord_id == discordId then
            done({ ok = false, message = 'The owner is already attached to this business.' })
            return
        end

        local function insertEmployee()
            Database.single('SELECT id FROM business_employees WHERE business_id = ? AND discord_id = ? AND status = "active" LIMIT 1', {
                businessId,
                discordId
            }, function(existing)
                if existing then
                    done({ ok = false, message = 'That employee is already on this payroll.' })
                    return
                end

                Database.insert('INSERT INTO business_employees (business_id, discord_id, display_name, title, added_by, status) VALUES (?, ?, ?, ?, ?, "active")', {
                    businessId,
                    discordId,
                    displayName,
                    title,
                    actorLabel(src)
                }, function(insertId)
                    if not insertId then
                        done({ ok = false, message = 'Could not add employee.' })
                        return
                    end

                    logAction(src, ('added employee %s to business %s'):format(discordId, businessId))
                    refreshOpenUis()
                    done({ ok = true, message = 'Employee added.' })
                end)
            end)
        end

        if Config.BusinessRules.AllowEmployeesInMultipleBusinesses then
            insertEmployee()
            return
        end

        Database.single('SELECT e.id FROM business_employees e INNER JOIN businesses b ON b.id = e.business_id WHERE e.discord_id = ? AND e.status = "active" AND b.status = "active" LIMIT 1', {
            discordId
        }, function(existing)
            if existing then
                done({ ok = false, message = 'That member is already employed by another business.' })
            else
                insertEmployee()
            end
        end)
    end)
end

Handlers['business:removeEmployee'] = function(src, payload, done)
    local employeeId = tonumber(payload.employeeId)
    if not employeeId then
        done({ ok = false, message = 'Employee is required.' })
        return
    end

    Database.single('SELECT * FROM business_employees WHERE id = ? AND status = "active" LIMIT 1', {
        employeeId
    }, function(employee)
        if not employee then
            done({ ok = false, message = 'Employee was not found.' })
            return
        end

        fetchBusiness(employee.business_id, function(business)
            if not business or not assertOwner(src, business, done) then
                return
            end

            Database.update('UPDATE business_employees SET status = "removed" WHERE id = ?', {
                employeeId
            }, function()
                local activeShift = ActiveShiftsByDiscord[employee.discord_id]
                if activeShift and activeShift.businessId == tonumber(employee.business_id) then
                    endActiveShift(activeShift.source, 'ended_removed_from_payroll')
                end

                logAction(src, ('removed employee %s from business %s'):format(employee.discord_id, employee.business_id))
                refreshOpenUis()
                done({ ok = true, message = 'Employee removed.' })
            end)
        end)
    end)
end

Handlers['business:setEmployeeTitle'] = function(src, payload, done)
    local employeeId = tonumber(payload.employeeId)
    local title = sanitizeText(payload.title, 80)

    if not employeeId or title == '' then
        done({ ok = false, message = 'Employee and title are required.' })
        return
    end

    Database.single('SELECT * FROM business_employees WHERE id = ? AND status = "active" LIMIT 1', {
        employeeId
    }, function(employee)
        if not employee then
            done({ ok = false, message = 'Employee was not found.' })
            return
        end

        fetchBusiness(employee.business_id, function(business)
            if not business or not assertOwner(src, business, done) then
                return
            end

            Database.update('UPDATE business_employees SET title = ? WHERE id = ?', {
                title,
                employeeId
            }, function()
                refreshOpenUis()
                done({ ok = true, message = 'Employee title updated.' })
            end)
        end)
    end)
end

Handlers['admin:getData'] = function(src, _, done)
    if not assertAdmin(src, done) then
        return
    end

    Database.query('SELECT * FROM businesses ORDER BY status ASC, name ASC', {}, function(rows)
        enrichBusinesses(rows or {}, function(businesses)
            done({
                ok = true,
                data = {
                    businesses = businesses,
                    onlinePlayers = onlinePlayers()
                }
            })
        end)
    end)
end

Handlers['admin:createBusiness'] = function(src, payload, done)
    if not assertAdmin(src, done) then
        return
    end

    local input, errorMessage = validateBusinessInput(payload)
    if not input then
        done({ ok = false, message = errorMessage })
        return
    end

    local assignmentMode = sanitizeText(payload.assignmentMode or 'offline', 20)
    if assignmentMode == 'online' then
        local ownerSource = tonumber(payload.ownerSource)
        if not ownerSource or not GetPlayerName(ownerSource) then
            done({ ok = false, message = 'Selected player is not online.' })
            return
        end

        local ownerDiscordId = getDiscordId(ownerSource)
        if not ownerDiscordId then
            done({ ok = false, message = 'Selected player does not have a Discord identifier.' })
            return
        end

        createBusinessWithOwner(src, input, ownerDiscordId, getPlayerDisplayName(ownerSource), done)
        return
    end

    local ownerDiscordId = normalizeDiscordId(payload.ownerDiscordId)
    local ownerDisplayName = sanitizeText(payload.ownerDisplayName, 80)

    if not isValidDiscordId(ownerDiscordId) then
        done({ ok = false, message = 'Valid owner Discord ID is required.' })
        return
    end

    if ownerDisplayName == '' then
        done({ ok = false, message = 'Owner display name is required.' })
        return
    end

    createBusinessWithOwner(src, input, ownerDiscordId, ownerDisplayName, done)
end

Handlers['admin:updateBusiness'] = function(src, payload, done)
    if not assertAdmin(src, done) then
        return
    end

    local businessId = tonumber(payload.businessId)
    if not businessId then
        done({ ok = false, message = 'Business is required.' })
        return
    end

    local input, errorMessage = validateBusinessInput(payload)
    if not input then
        done({ ok = false, message = errorMessage })
        return
    end

    local ownerDiscordId = normalizeDiscordId(payload.ownerDiscordId)
    local ownerDisplayName = sanitizeText(payload.ownerDisplayName, 80)
    local status = normalizeStatus(payload.status, 'active')

    if not isValidDiscordId(ownerDiscordId) then
        done({ ok = false, message = 'Valid owner Discord ID is required.' })
        return
    end

    if ownerDisplayName == '' then
        done({ ok = false, message = 'Owner display name is required.' })
        return
    end

    fetchBusiness(businessId, function(existing)
        if not existing then
            done({ ok = false, message = 'Business was not found.' })
            return
        end

        local function updateBusiness()
            Database.update('UPDATE businesses SET name = ?, type = ?, owner_discord_id = ?, owner_display_name = ?, status = ? WHERE id = ?', {
                input.name,
                input.type,
                ownerDiscordId,
                ownerDisplayName,
                status,
                businessId
            }, function()
                if status == 'archived' then
                    archiveBusinessSideEffects(businessId, 'ended_business_archived')
                end

                logAction(src, ('updated business %s'):format(businessId))
                refreshOpenUis()
                done({ ok = true, message = 'Business updated.' })
            end)
        end

        if Config.BusinessRules.AllowMultipleBusinessesPerOwner or status ~= 'active' then
            updateBusiness()
            return
        end

        Database.single('SELECT id FROM businesses WHERE owner_discord_id = ? AND status = "active" AND id <> ? LIMIT 1', {
            ownerDiscordId,
            businessId
        }, function(conflict)
            if conflict then
                done({ ok = false, message = 'That owner already has an active business.' })
            else
                updateBusiness()
            end
        end)
    end)
end

Handlers['admin:archiveBusiness'] = function(src, payload, done)
    if not assertAdmin(src, done) then
        return
    end

    local businessId = tonumber(payload.businessId)
    if not businessId then
        done({ ok = false, message = 'Business is required.' })
        return
    end

    fetchBusiness(businessId, function(business)
        if not business then
            done({ ok = false, message = 'Business was not found.' })
            return
        end

        Database.update('UPDATE businesses SET status = "archived" WHERE id = ?', {
            businessId
        }, function()
            archiveBusinessSideEffects(businessId, 'ended_business_archived')
            logAction(src, ('archived business %s'):format(businessId))
            refreshOpenUis()
            done({ ok = true, message = 'Business archived.' })
        end)
    end)
end

Handlers['admin:getOnlinePlayers'] = function(src, _, done)
    if not assertAdmin(src, done) then
        return
    end

    done({
        ok = true,
        data = onlinePlayers()
    })
end

RegisterNetEvent('ssrp_business:server:nuiRequest', function(requestId, action, payload)
    local src = source
    local handler = Handlers[action]

    if not handler then
        respond(src, requestId, { ok = false, message = 'Unknown business action.' })
        return
    end

    handler(src, payload or {}, function(response)
        respond(src, requestId, response)
    end)
end)

RegisterNetEvent('ssrp_business:server:setAfk', function(isAfk)
    setAfkState(source, isAfk and true or false)
end)

RegisterNetEvent('ssrp_business:server:afkAutoEnd', function()
    if not Config.AFK.AutoEndShift then
        return
    end

    endActiveShift(source, 'ended_afk_timeout')
end)

RegisterCommand('business', function(src)
    if src == 0 then
        print('[ssrp_business] /business can only be opened by a player.')
        return
    end

    TriggerClientEvent('ssrp_business:client:openUi', src, 'business')
end, false)

RegisterCommand('businessadmin', function(src)
    if src == 0 then
        print('[ssrp_business] /businessadmin can only be opened by a player.')
        return
    end

    if not isAdmin(src) then
        notify(src, 'error', 'You do not have business admin access.')
        return
    end

    TriggerClientEvent('ssrp_business:client:openUi', src, 'admin')
end, false)

AddEventHandler('playerDropped', function()
    local src = source
    if Config.Shifts.EndOnDisconnect and ActiveShiftsBySource[src] then
        endActiveShift(src, 'ended_disconnected')
    end
end)

CreateThread(function()
    Wait(1500)

    if Config.Shifts.CloseOpenShiftsOnResourceStart then
        Database.update('UPDATE business_shifts SET shift_end = NOW(), total_minutes = TIMESTAMPDIFF(MINUTE, shift_start, NOW()), status = "ended_resource_restart", is_afk = 0 WHERE shift_end IS NULL AND status IN ("active", "afk")', {}, function()
            debugLog('Closed open shifts from previous resource session.')
        end)
    end
end)

exports('IsPlayerOnBusinessShift', function(playerOrDiscord)
    return resolveShift(playerOrDiscord) ~= nil
end)

exports('GetPlayerActiveBusiness', function(playerOrDiscord)
    return shiftToPublic(resolveShift(playerOrDiscord))
end)

exports('IsPlayerBusinessShiftAFK', function(playerOrDiscord)
    local shift = resolveShift(playerOrDiscord)
    return shift and shift.afk or false
end)

exports('CanReceiveBusinessPay', function(playerOrDiscord)
    local shift = resolveShift(playerOrDiscord)
    if not shift then
        return false
    end

    if Config.AFK.AutoPausePay and shift.afk then
        return false
    end

    return true
end)
