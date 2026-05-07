# SSRP Business

FiveM resource for SSRP-style business management, employee payroll rosters, shift tracking, AFK state, and clean integration hooks for an existing Hybrid Pay salary system.

## Install

1. Put this folder in your resources directory. The recommended resource folder name is `ssrp_business`, but `Businesspro` is fine if that is what your server uses.
2. Import [sql/ssrp_business.sql](sql/ssrp_business.sql) into your oxmysql database.
3. Install `oxmysql` if your server does not already have it. The folder/resource must be named exactly `oxmysql`.
4. Add this to `server.cfg` after oxmysql:

```cfg
ensure oxmysql
ensure Businesspro
```

Use `ensure ssrp_business` instead if your resource folder is named `ssrp_business`.

5. Configure [config.lua](config.lua):
   - `Config.Admin.AcePermissions`
   - `Config.Admin.DiscordRoleIds`
   - `Config.BusinessTypes`
   - `Config.AFK`
   - `Config.BusinessRules`

## Commands

- `/business` opens the owner/employee UI.
- `/businessadmin` opens the Director/Admin UI.

`/businessadmin` is server validated through ACE and optional Discord role checks. Example ACE setup:

```cfg
add_ace group.admin ssrp.business.admin allow
add_principal identifier.discord:123456789012345678 group.admin
```

FiveM does not expose Discord roles natively. If you use a bridge such as `Badger_Discord_API` or your own Discord permission resource, set `Config.Admin.DiscordRoleResource` and add role IDs to `Config.Admin.DiscordRoleIds`.

## Hybrid Pay Integration

This resource does not set pay amounts. Your existing SSRP Hybrid Pay system should read shift state through exports.

If your folder is named `Businesspro`, use:

```lua
local src = source

if exports['Businesspro']:IsPlayerOnBusinessShift(src) then
    local business = exports['Businesspro']:GetPlayerActiveBusiness(src)

    if business and exports['Businesspro']:CanReceiveBusinessPay(src) then
        -- Apply your existing altered salary logic here.
    end
end
```

If your folder is named `ssrp_business`, use:

```lua
local src = source

if exports['ssrp_business']:IsPlayerOnBusinessShift(src) then
    local business = exports['ssrp_business']:GetPlayerActiveBusiness(src)

    if business and exports['ssrp_business']:CanReceiveBusinessPay(src) then
        -- business.businessId
        -- business.businessName
        -- business.businessType
        -- business.isAfk
        -- Apply your existing altered salary logic here.
    else
        -- Player is AFK or otherwise not eligible for business shift salary.
    end
end
```

Server events are also fired for integrations:

```lua
AddEventHandler('ssrp_business:shiftStarted', function(src, shift)
    print(('Business shift started: %s at %s'):format(shift.displayName, shift.businessName))
end)

AddEventHandler('ssrp_business:shiftEnded', function(src, shift)
    print(('Business shift ended: %s'):format(shift.displayName))
end)

AddEventHandler('ssrp_business:shiftAfkChanged', function(src, shift)
    print(('Business shift AFK changed: %s AFK=%s'):format(shift.displayName, tostring(shift.isAfk)))
end)
```

## Exports

- `IsPlayerOnBusinessShift(sourceOrDiscordId)` returns `true` when the player has an active business shift.
- `GetPlayerActiveBusiness(sourceOrDiscordId)` returns active business/shift data or `nil`.
- `IsPlayerBusinessShiftAFK(sourceOrDiscordId)` returns AFK state.
- `CanReceiveBusinessPay(sourceOrDiscordId)` returns `false` while AFK when `Config.AFK.AutoPausePay` is enabled.

## Notes

- All owner/admin actions are validated server side.
- Duplicate active shifts and duplicate active employee entries are blocked in server logic.
- Open shifts can be automatically closed on resource start with `Config.Shifts.CloseOpenShiftsOnResourceStart`.
- AFK detection marks shifts AFK, pauses pay through `CanReceiveBusinessPay`, and can optionally auto-end shifts after `Config.AFK.AutoEndSeconds`.
