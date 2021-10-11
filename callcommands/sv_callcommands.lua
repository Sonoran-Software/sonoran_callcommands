--[[
    Sonaran CAD Plugins

    Plugin Name: callcommands
    Creator: SonoranCAD
    Description: Implements 311/511/911 commands
]]

CreateThread(function() Config.LoadPlugin("callcommands", function(pluginConfig)
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
        function HandleCivilianCall(type, typeObj, source, args, rawCommand)
            local isEmergency = typeObj.isEmergency
            local identifier = GetIdentifiers(source)[Config.primaryIdentifier]
            local callLocation = LocationCache[source] ~= nil and LocationCache[source].location or 'Unknown'
            -- Checking if there are any description arguments.
            if args[1] then
                local description = table.concat(args, " ")
                if typeObj.descriptionPrefix ~= "" then
                    description = typeObj.descriptionPrefix.." "..description
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
                TriggerEvent('SonoranCAD::callcommands:SendCallApi', isEmergency, caller, callLocation, description, source, nil, nil, type)
                -- Sending the user a message stating the call has been sent
                TriggerClientEvent("chat:addMessage", source, {args = {"^0^5^*[SonoranCAD]^r ", "^7Your call has been sent to dispatch. Help is on the way!"}})
            else
                -- Throwing an error message due to now call description stated
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "You need to specify a call description."}})
            end
        end
    
        CreateThread(function()
            for _, call in pairs(pluginConfig.callTypes) do
                RegisterCommand(call.command, function(source, args, rawCommand)
                    HandleCivilianCall(call.command, call, source, args, rawCommand)
                end)
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
        AddEventHandler('SonoranCAD::callcommands:SendCallApi', function(emergency, caller, location, description, source, silenceAlert, useCallLocation, type)
            if location == '' then
                location = LocationCache[source] ~= nil and LocationCache[source].location or 'Unknown'
            end
            -- send an event to be consumed by other resources
            local uid = uuid()
            TriggerEvent("SonoranCAD::callcommands:cadIncomingCall", emergency, caller, location, description, source, uid, type)
            if silenceAlert == nil then silenceAlert = false end
            if useCallLocation == nil then useCallLocation = false end
            local postal = ""
            if isPluginLoaded("postals") and PostalsCache ~= nil then
                postal = PostalsCache[source]
            end
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
                        ['uuid'] = uid,
                        ['silentAlert'] = silenceAlert,
                        ['useCallLocation'] = useCallLocation,
                        ['callPostal'] = postal,
                        ['callLocationx'] = LocationCache[source].position.x,
                        ['callLocationy'] = LocationCache[source].position.y,
                        ['callLocationz'] = LocationCache[source].position.z
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

        --TriggerEvent("SonoranCAD::pushevents:UnitPanic", unit, body.data.identId)
        AddEventHandler("SonoranCAD::pushevents:UnitPanic", function(unit, ident, isPanic)
            debugLog(("triggered panic %s"):format(json.encode(unit)))
            if not isPanic then
                return debugLog("ignore panic, was toggled off")
            end
            local unit = GetUnitCache()[GetUnitById(ident)]
            if unit then
                local player = GetSourceByApiId(unit.data.apiIds)
                if player then
                    sendPanic(player)
                end
            end
        end)
        function sendPanic(source)
            -- Determine identifier
            local source = tostring(source)
            local identifier = GetIdentifiers(source)[Config.primaryIdentifier]
            -- Process panic POST request
            if pluginConfig.addPanicCall then
                local unit = GetUnitByPlayerId(source)
                if not unit then
                    debugLog("Caller not a unit, ignoring.")
                    return
                end
                local postal = ""
                if isPluginLoaded("postals") and PostalsCache[source] ~= nil then
                    postal = PostalsCache[source]
                else
                    debugLog("postal is nil?!")
                end
                local data = {
                    ['serverId'] = Config.serverId, 
                    ['isEmergency'] = true, 
                    ['caller'] = unit.data.name, 
                    ['location'] = unit.location, 
                    ['description'] = ("Unit %s has pressed their panic button!"):format(unit.data.unitNum),
                    ['metaData'] = {
                        ['callerPlayerId'] = source,
                        ['callerApiId'] = GetIdentifiers(source)[Config.primaryIdentifier],
                        ['uuid'] = uuid(),
                        ['silentAlert'] = false,
                        ['useCallLocation'] = false,
                        ['callPostal'] = postal,
                        ['callLocationx'] = LocationCache[source].position.x,
                        ['callLocationy'] = LocationCache[source].position.y,
                        ['callLocationz'] = LocationCache[source].position.z
                    }
                }
                debugLog(("perform panic request %s"):format(json.encode(data)))
                performApiRequest({data}, 'CALL_911', function(resp) debugLog(resp) end)
            end
            performApiRequest({{['isPanic'] = true, ['apiId'] = identifier}}, 'UNIT_PANIC', function() end)
        end
    
    end
end) end)

