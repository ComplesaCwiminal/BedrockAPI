    local bedrockCore = require("BedrockAPI.BedrockCore")
    local bedrockInput = require("BedrockAPI.BedrockInput")
    local BedrockNetworkDevice = require("BedrockAPI.BedrockNetworkDevice")

    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new():addModule(BedrockNetworkDevice):addModule(bedrockInput)

    -- build your core so it'll be run in the update loop
    coreInstance:build()

    local configFile = "LabWareDevice.cfg"
    local descriptorLocation

    local function quit(reasonCode)
        BedrockNetworkDevice.disconnect(reasonCode)
    end

    local function main()

        -- Check the config exists, read it if it does or quit after making it if it doesn't.
        if fs.exists(configFile) then
            local fh = fs.open(configFile, "r")
            descriptorLocation = fh.readAll()
            fh.close()
        else
            fs.open(configFile, "w").close()
            error(string.format("Missing config file! (%s) \nNote: The file has been created for you automatically, but is empty!", configFile), 0)
        end
        
        local deviceDescriptor = require(descriptorLocation)

        BedrockNetworkDevice.endpoints = {
            discoveryProtocol = "LabwareDeviceLookup",
            discoveryName = "LabwareServer",
            encryptedMessageProtocol = "LabwareMessage",
            messageACKProtocol = "LabwareMessageACK",
            callResponseProtocol = "LabwareCallResponse",
            authProtocol = "LabwareAuth",
            dns = "dns", -- This one is from CC itself, but consistency.
        }

        local endpointsLookup = BedrockNetworkDevice.endpoints

        BedrockNetworkDevice.addHandler(function ()
            return true
        end, function (msg)
            if msg ~= nil and msg.deviceRequest == true and msg.user ~= nil then
                local params = msg.params
                if type(params) == "string" then
                    local tbl = textutils.unserialise(params)

                    if tbl ~= nil then
                        params = tbl
                    end
                end

                if type(params) == "table" then
                    if msg.type == "variable" then
                        if msg.fieldName ~= nil and deviceDescriptor.variables[string.lower(msg.fieldName)] ~= nil then
                            if msg.varAction == "get" and type(deviceDescriptor.variables[string.lower(msg.fieldName)].getCallback) == "function" then
                                BedrockNetworkDevice.sendMessage({content = textutils.serialise(table.pack(deviceDescriptor.variables[string.lower(msg.fieldName)]:getCallback(params))), deviceResponse = true, routeTo = msg.user}, false, endpointsLookup.encryptedMessageProtocol) -- Give them what they're looking for.
                            elseif msg.varAction == "set" and type(deviceDescriptor.variables[string.lower(msg.fieldName)].modifyCallback) == "function" then
                                deviceDescriptor.variables[string.lower(msg.fieldName)]:modifyCallback(table.unpack(params or {}))
                            end
                        end
                    elseif msg.type == "function" then
                        if msg.fieldName ~= nil and type(deviceDescriptor.functions[string.lower(msg.fieldName)]) == "function" then
                            deviceDescriptor.functions[string.lower(msg.fieldName)](table.unpack(params or {}))
                        end
                    end
                end
            end
        end)
        
        deviceDescriptor.quit = quit

        if type(deviceDescriptor.peerActions) == "table" then

            deviceDescriptor.peerActions.requestConnection = function ()
                -- TODO
            end
            deviceDescriptor.peerActions.manageConnection = function ()
                
            end

            deviceDescriptor.peerActions.find = function ()
                
            end
            -- Things the descriptor should provide on it's own are callbacks for when it is discovered, and for connection requests.
        end


        local UUIDgen = function ()
            -- Make a gen 4 UUID or something i dunno.
            return BedrockNetworkDevice.ecc.random.random()
        end

        deviceDescriptor.init({coreInstance = coreInstance, bedrockInput = bedrockInput, makeUUID = UUIDgen})
        if deviceDescriptor.UUID == nil then
            deviceDescriptor.UUID = UUIDgen()
        end

        BedrockNetworkDevice.onConnect = function ()
            -- uhhhh
            local sendDescriptor = {
                events = {},
                variables = {},
                functions = {}
            }

            for i,v in pairs(deviceDescriptor.events) do
                deviceDescriptor.events[i] = function (...) BedrockNetworkDevice.sendMessage({eventFire = true, eventName = i, params = textutils.serialise({...})}, false, endpointsLookup.encryptedMessageProtocol) end
                sendDescriptor.events[i] = true
            end

                        -- The lua language server is funny because it acts like this is a strict type language but like it's not so let me abuse my typing in peace.
            for i,v in pairs(deviceDescriptor.variables) do
                sendDescriptor.variables[i] = v.value
            end

            for i,v in pairs(deviceDescriptor.functions) do
                sendDescriptor.functions[i] = true
            end

            for i,v in pairs(deviceDescriptor) do
                if type(v) == "table" and sendDescriptor[i] == nil then
                    sendDescriptor[i] = textutils.serialise(v)
                elseif type(v) ~= "function" and sendDescriptor[i] == nil then
                    sendDescriptor[i] = v
                end
                  
            end
 
            local semiEphPriv, semiEphPub = BedrockNetworkDevice.ecc.keypair(BedrockNetworkDevice.ecc.random.random())


            BedrockNetworkDevice.sendMessage({deviceDescriptor = sendDescriptor, pubKey = semiEphPub, signature = BedrockNetworkDevice.ecc.sign(semiEphPriv, sendDescriptor)}, false, endpointsLookup.encryptedMessageProtocol) -- Labware devices send their device descriptors. Then just kinda sit idle. I'll figure it out one day
        end
        
        parallel.waitForAny(BedrockNetworkDevice.run())
    end

    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()