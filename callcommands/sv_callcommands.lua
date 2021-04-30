--[[
    Sonaran CAD Plugins

    Plugin Name: callcommands
    Creator: SonoranCAD
    Description: Implements 311/511/911 commands
]]

local pluginConfig = Config.GetPluginConfig("callcommands")

if pluginConfig.enabled then

    local random = math.random
    local function uuid()
        math.randomseed(os.time())
        local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
        return string.gsub(template, '[xy]', function (c)
            local v = (c == 'x') and random(0, 0xf) or random(8, 0xb)
            return string.format('%x', v)
        end)
    end
    -- 911/311 Handler
    function HandleCivilianCall(type, source, args, rawCommand)
        local isEmergency = type == "911" and true or false
        local identifier = GetIdentifiers(source)[Config.primaryIdentifier]
        local callLocation = LocationCache[source] ~= nil and LocationCache[source].location or 'Unknown'
        -- Checking if there are any description arguments.
        if args[1] then
            local description = table.concat(args, " ")
            if type == "511" then
                description = "(511 CALL) "..description
            end
            local caller = nil
            if isPluginLoaded("esxsupport") then
                -- Getting the ESX Identity Name
                GetIdentity(source, function(identity)
                    if identity.name ~= nil then
                        caller = identity.name
                    else
                        caller = GetPlayerName(source)
                        debugLog("Unable to get player name from ESX. Falled back to in-game name.")
                    end
                end)
                while caller == nil do
                    Wait(10)
                end
            else
                caller = GetPlayerName(source) 
            end
            -- Sending the API event
            TriggerEvent('SonoranCAD::callcommands:SendCallApi', isEmergency, caller, callLocation, description, source)
            -- Sending the user a message stating the call has been sent
            TriggerClientEvent("chat:addMessage", source, {args = {"^0^5^*[SonoranCAD]^r ", "^7Your call has been sent to dispatch. Help is on the way!"}})
        else
            -- Throwing an error message due to now call description stated
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "You need to specify a call description."}})
        end
    end

    CreateThread(function()
        if pluginConfig.enable911 then
            RegisterCommand('911', function(source, args, rawCommand)
                HandleCivilianCall("911", source, args, rawCommand)
            end, false)
        end
        if pluginConfig.enable511 then
            RegisterCommand('511', function(source, args, rawCommand)
                HandleCivilianCall("511", source, args, rawCommand)
            end, false)
        end
        if pluginConfig.enable311 then
            RegisterCommand('311', function(source, args, rawCommand)
                HandleCivilianCall("311", source, args, rawCommand)
            end, false)
        end
        if pluginConfig.enablePanic then
            RegisterCommand('panic', function(source, args, rawCommand)
                sendPanic(source)
            end, false)
            -- Client Panic request (to be used by other resources)
            RegisterNetEvent('SonoranCAD::callcommands:SendPanicApi')
            AddEventHandler('SonoranCAD::callcommands:SendPanicApi', function(source)
                sendPanic(source)
            end)
        end

    end)

    -- Client Call request
    RegisterServerEvent('SonoranCAD::callcommands:SendCallApi')
    AddEventHandler('SonoranCAD::callcommands:SendCallApi', function(emergency, caller, location, description, source)
        if location == '' then
            location = LocationCache[source] ~= nil and LocationCache[source].location or 'Unknown'
        end
        -- send an event to be consumed by other resources
        local uid = uuid()
        TriggerEvent("SonoranCAD::callcommands:cadIncomingCall", emergency, caller, location, description, source, uid)
        if Config.apiSendEnabled then
            local data = {
                ['serverId'] = Config.serverId, 
                ['isEmergency'] = emergency, 
                ['caller'] = caller, 
                ['location'] = location, 
                ['description'] = description,
                ['metaData'] = {
                    ['callerPlayerId'] = source,
                    ['callerApiId'] = GetIdentifiers(source)[Config.primaryIdentifier],
                    ['uuid'] = uid
                }
            }
            debugLog("sending call!")
            performApiRequest({data}, 'CALL_911', function(response) 
                if response:match("EMERGENCY CALL ADDED ID:") then
                    TriggerEvent("SonoranCAD::callcommands:EmergencyCallAdd", source, response:match("%d+"))
                end
            end)
        else
            debugPrint("[SonoranCAD] API sending is disabled. Incoming call ignored.")
        end
    end)

    ---------------------------------
    -- Unit Panic
    ---------------------------------
    -- shared function to send panic signals
    function sendPanic(source)
        -- Determine identifier
        local identifier = GetIdentifiers(source)[Config.primaryIdentifier]
        -- Process panic POST request
        performApiRequest({{['isPanic'] = true, ['apiId'] = identifier}}, 'UNIT_PANIC', function() end)
    end

end