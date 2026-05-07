Config = {}

Config.Debug = false

Config.Database = {
    Driver = 'oxmysql',
    Resource = 'oxmysql',
    WaitForStartMs = 30000
}

Config.Admin = {
    AcePermissions = {
        'ssrp.business.admin',
        'command.businessadmin'
    },

    -- FiveM does not expose Discord roles by default. Add role IDs here, then
    -- configure DiscordRoleResource or replace HasDiscordRole with your bridge.
    DiscordRoleIds = {
        -- '123456789012345678'
    },

    -- Examples: 'Badger_Discord_API', 'discord_perms', or your own role bridge.
    DiscordRoleResource = nil,

    HasDiscordRole = function(source, roleId)
        local resource = Config.Admin.DiscordRoleResource
        if not resource or resource == '' or not roleId or roleId == '' then
            return false
        end

        if GetResourceState(resource) ~= 'started' then
            return false
        end

        local checks = {
            function() return exports[resource]:IsRolePresent(source, roleId) end,
            function() return exports[resource]:HasRole(source, roleId) end,
            function() return exports[resource]:hasRole(source, roleId) end
        }

        for _, check in ipairs(checks) do
            local ok, result = pcall(check)
            if ok and result then
                return true
            end
        end

        return false
    end
}

Config.BusinessTypes = {
    'Restaurant',
    'Bar',
    'Mechanic',
    'Dealership',
    'Retail',
    'Security',
    'Entertainment',
    'Logistics',
    'Legal',
    'Medical'
}

Config.BusinessRules = {
    AllowMultipleBusinessesPerOwner = false,
    AllowEmployeesInMultipleBusinesses = true,
    AllowOwnerAsEmployee = false
}

Config.Shifts = {
    EndOnDisconnect = true,
    CloseOpenShiftsOnResourceStart = true,
    HistoryLimit = 25
}

Config.AFK = {
    TimeoutSeconds = 600,
    AutoPausePay = true,
    AutoEndShift = false,
    AutoEndSeconds = 1800,
    CheckIntervalMs = 1000,
    MovementDistance = 0.75,
    ActivityControls = {
        22, 24, 25, 30, 31, 32, 33, 34, 35, 44, 45, 46, 47,
        51, 52, 75, 76, 140, 141, 142, 143, 257
    }
}

Config.Integration = {
    ShiftStartedEvent = 'ssrp_business:shiftStarted',
    ShiftEndedEvent = 'ssrp_business:shiftEnded',
    ShiftAfkChangedEvent = 'ssrp_business:shiftAfkChanged',

    Exports = {
        IsOnShift = 'IsPlayerOnBusinessShift',
        GetActiveBusiness = 'GetPlayerActiveBusiness',
        IsAfk = 'IsPlayerBusinessShiftAFK',
        CanReceivePay = 'CanReceiveBusinessPay'
    }
}

Config.UI = {
    Title = 'SSRP Business',
    Theme = {
        Gold = '#d5a94f',
        Blue = '#3b82f6',
        Background = '#080b12',
        Panel = '#101722',
        PanelSoft = '#162033',
        Text = '#f7f1df',
        Muted = '#94a3b8',
        Danger = '#ef4444',
        Success = '#22c55e'
    }
}
