local uiOpen = false
local onBusinessShift = false
local activeShift = nil
local clientAfk = false
local lastActivity = GetGameTimer()
local lastCoords = nil

local function clientConfig()
    return {
        title = Config.UI.Title,
        theme = Config.UI.Theme,
        businessTypes = Config.BusinessTypes,
        afk = Config.AFK
    }
end

local function notifyNative(message)
    BeginTextCommandThefeedPost('STRING')
    AddTextComponentSubstringPlayerName(('SSRP Business: %s'):format(message))
    EndTextCommandThefeedPostTicker(false, false)
end

local function sendToast(kind, message)
    if uiOpen then
        SendNUIMessage({
            type = 'notify',
            kind = kind or 'info',
            message = message
        })
    else
        notifyNative(message)
    end
end

local function openUi(view)
    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        type = 'open',
        view = view or 'business',
        config = clientConfig()
    })
end

local function closeUi()
    uiOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterNetEvent('ssrp_business:client:openUi', function(view)
    openUi(view)
end)

RegisterNetEvent('ssrp_business:client:notify', function(kind, message)
    sendToast(kind, message)
end)

RegisterNetEvent('ssrp_business:client:refreshOpenUi', function()
    if uiOpen then
        SendNUIMessage({ type = 'refresh' })
    end
end)

RegisterNetEvent('ssrp_business:client:shiftState', function(isOnShift, shift)
    onBusinessShift = isOnShift and true or false
    activeShift = shift
    clientAfk = shift and shift.isAfk or false
    lastActivity = GetGameTimer()
    lastCoords = nil

    SendNUIMessage({
        type = 'shiftState',
        onShift = onBusinessShift,
        shift = activeShift
    })
end)

RegisterNetEvent('ssrp_business:client:nuiResponse', function(requestId, response)
    SendNUIMessage({
        type = 'response',
        requestId = requestId,
        response = response
    })
end)

RegisterNUICallback('close', function(_, cb)
    closeUi()
    cb({ ok = true })
end)

RegisterNUICallback('request', function(data, cb)
    if type(data) ~= 'table' or not data.requestId or not data.action then
        cb({ ok = false, message = 'Invalid request.' })
        return
    end

    TriggerServerEvent('ssrp_business:server:nuiRequest', data.requestId, data.action, data.payload or {})
    cb({ ok = true })
end)

local function hasActivity()
    local ped = PlayerPedId()
    if not DoesEntityExist(ped) then
        return false
    end

    local coords = GetEntityCoords(ped)
    if not lastCoords then
        lastCoords = coords
        return true
    end

    local movementDistance = Config.AFK.MovementDistance or 0.75
    if #(coords - lastCoords) >= movementDistance then
        lastCoords = coords
        return true
    end

    for _, control in ipairs(Config.AFK.ActivityControls or {}) do
        if IsControlPressed(0, control) or IsControlJustPressed(0, control) then
            return true
        end
    end

    return IsPedShooting(ped)
        or IsPedJumping(ped)
        or IsPedClimbing(ped)
        or IsPedGettingIntoAVehicle(ped)
end

CreateThread(function()
    while true do
        if not onBusinessShift then
            Wait(1500)
            lastActivity = GetGameTimer()
            lastCoords = nil
        else
            Wait(Config.AFK.CheckIntervalMs or 1000)

            if hasActivity() then
                lastActivity = GetGameTimer()
                if clientAfk then
                    clientAfk = false
                    TriggerServerEvent('ssrp_business:server:setAfk', false)
                end
            else
                local idleSeconds = math.floor((GetGameTimer() - lastActivity) / 1000)

                if not clientAfk and idleSeconds >= (Config.AFK.TimeoutSeconds or 600) then
                    clientAfk = true
                    TriggerServerEvent('ssrp_business:server:setAfk', true)
                end

                if Config.AFK.AutoEndShift and idleSeconds >= (Config.AFK.AutoEndSeconds or 1800) then
                    TriggerServerEvent('ssrp_business:server:afkAutoEnd')
                    onBusinessShift = false
                end
            end
        end
    end
end)
