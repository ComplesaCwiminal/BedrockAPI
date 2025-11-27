    local bedrockCore = require("BedrockAPI.BedrockCore")
    local BedrockNetworkServer = require("BedrockAPI.BedrockNetworkServer")

    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new():addModule(BedrockNetworkServer)

    -- build your core so it'll be run in the update loop
    coreInstance:build()

    local devices = {}
    local users = {}

    BedrockNetworkServer.endpoints = {
            discoveryProtocol = "LabwareDeviceLookup",
            discoveryName = "LabwareServer",
            encryptedMessageProtocol = "LabwareMessage",
            messageACKProtocol = "LabwareMessageACK",
            callResponseProtocol = "LabwareCallResponse",
            authProtocol = "LabwareAuth",
            dns = "dns", -- This one is from CC itself, but consistency.
        }

    -- Your own main function. When it completes your program is over
    local function main()
        local endpointsLookup = BedrockNetworkServer.endpoints
        local clients = BedrockNetworkServer.clients
        local ecc = BedrockNetworkServer.ecc
        
        BedrockNetworkServer.addConnectHandler("setup", function (self)
            self.peers = {}
            self.prospectivePeers = {}
            self.rejectedPeers = {}
        end)
        BedrockNetworkServer.addDisconnectHandler("removeDevice", function (self)
            if devices[self.clientID] ~= nil then

                devices[self.clientID] = nil

                for i,v in pairs(users) do
                    local success, value = bedrockCore.GetSharedValue(tostring(self.clientID))
                    BedrockNetworkServer.sendMessage(v, {deviceDetached = true, id = self.clientID}, endpointsLookup.encryptedMessageProtocol)
                end
            end

            if self.peers ~= nil then
                for i,v in pairs(self.peers) do
                    if clients[i].peers ~= nil then
                        BedrockNetworkServer.sendMessage(i, {peerDisconnected = true, id = self.clientID}, endpointsLookup.encryptedMessageProtocol)
                    end
                end
            end
        end)

        -- Plug and play? Maybe. Universal? No fucking idea quite frankly.
        BedrockNetworkServer.addHandler("DisconnectHandler", function (sender, message, protocol)
        return protocol == endpointsLookup.encryptedMessageProtocol and type(message) == "table" and message.disconnectRequest ~= nil
        end, function(sender, message, protocol)
            clients[sender]:disconnect(message.reasonCode or 0)

        end)

        BedrockNetworkServer.addHandler("DescriptorHandler", function (sender, message, protocol)
            return type(message) == "table" and message.deviceDescriptor ~= nil
        end,
        function (sender, message, protocol)

            -- Holy fucking shit I get to use the shared values system!!!!!
            local good, descriptorText = pcall(textutils.serialize, message.deviceDescriptor)

            if not good then
                return
            end
            
            -- Make sure to encrypt anything important. We're just gonna sign this though.

            local success, value = bedrockCore.AddSharedValue(descriptorText, tostring(clients[sender].clientID))

            if success == false then
                -- In this case this info is just metadata so refreshing it isn't problematic. Some stuff could be state though so pay attention.
                bedrockCore.RemoveSharedValue(tostring(clients[sender].clientID), clients[sender].clientID)
                _, value = bedrockCore.AddSharedValue(descriptorText, tostring(clients[sender].clientID))
            end

            devices[clients[sender].clientID] = clients[sender].clientID

            value.pubKey = message.pubKey -- may or may not exist. so glhf
            value.signature = message.signature
            value.hash = ecc.sha256.hmac(descriptorText, clients[sender].sharedSecret)
            value.creator = sender

            -- Oh svs you so surprisingly effective for security.
            value.onModify = function (self, newValue, signature)
                if (self.pubKey ~= nil and signature ~= nil and ecc.verify(self.pubKey, newValue, signature)) or (self.hash == ecc.sha256.hmac(self.value, signature)) then
                    if signature ~= nil then
                        self.signature = signature
                    end
                    self.hash = ecc.sha256.hmac(newValue, clients[sender].sharedSecret)
                    return true, newValue
                end
                return false
            end
        
            value.onRead = function (self)
                -- How do I do error correcting I wonder.
                return true, self.value -- We don't need to protect read, since it's nost a secret. Others might be.
            end
        
            value.onRemove = function (self, identity)
                -- Nil should only be from the server GAURD AGAINST THIS
                return self.creator == identity or identity == nil
            end

            for i,v in pairs(users) do
                local success3, value3 = bedrockCore.GetSharedValue(tostring(clients[sender].clientID))
                BedrockNetworkServer.sendMessage(v, {deviceAttached = true, descriptor = value3, id = clients[sender].clientID}, protocol)
            end
        end)

        -- Users hold an elevated level of control
        BedrockNetworkServer.addHandler("UserHandler", function (sender, message, protocol)
        return type(message) == "table" and message.userLogin == true
        end, function(sender,message,protocol)
            if type(message.username) == "string" and type(message.password) == "string" then
                if fs.exists("trusted_user.creds") then
                    local fh = fs.open("trusted_user.creds", "r")
                    local contents = fh.readAll()
                    fh.close()
                    local success, credTable = pcall(textutils.unserialise, contents)
                    -- Make sure deserialisation and checksumms work out.
                    if success and credTable.checksum == tostring(ecc.sha256.hmac(credTable.contents, "checksum")) then
                        local contentSuccess, contentTable = pcall(textutils.unserialise, credTable.contents)
                        if contentSuccess then
                            if contentTable.username == message.username then
                                -- Always salt your passwords. Maybe obfuscate your usernames, but that's negotiable.
                                if tostring(ecc.sha256.pbkdf2(message.password, contentTable.pepper, 2048)) == contentTable.password then
                                    clients[sender].userAuthed = true
                                    users[sender] = sender
                                    return
                                end
                            end
                        end
                    else
                        print("Failed to deserialise the user credentials!")
                    end
                    rednet.send(sender, BedrockNetworkServer.generateError(008, true))
                else
                    if type(message.salt) == "string" then


                        local fh = fs.open("trusted_user.creds", "w")
                        message.pepper = tostring(ecc.random.random()) -- I'm hungry. Is pepper real in cryptography
                        message.password = tostring(ecc.sha256.pbkdf2(message.password, message.pepper, 2048))
                        local contents = textutils.serialise(message)

                        local savedTable = {
                            contents = contents,
                            checksum = tostring(ecc.sha256.hmac(contents, "checksum"))
                        }

                        fh.write(textutils.serialise(savedTable))
                        fh.close()
                        
                        clients[sender].userAuthed = true
                        users[sender] = sender
                        return
                    end
                    rednet.send(sender, BedrockNetworkServer.generateError(008, true)) -- skill issue :/
                end
            end
        end)


        BedrockNetworkServer.addHandler("CredProbeHandler", function (sender, message, protocol)
            -- A salt probe should be a string because it's the username
            return type(message) == "table" and type(message.saltProbe) == "string"
        end, function (sender, message, protocol)
            BedrockNetworkServer.handleTrustworthiness(sender, BedrockNetworkServer.messageWeights.protectedQuery) -- Make it less possible to probe for salts.
            if fs.exists("trusted_user.creds") then
                local fh = fs.open("trusted_user.creds", "r")
                local contents = fh.readAll()
                fh.close()
                local success, credTable = pcall(textutils.unserialise, contents)
                -- Make sure deserialisation and checksumms work out.
                if success and credTable.checksum == tostring(ecc.sha256.hmac(credTable.contents, "checksum")) then
                    local contentSuccess, contentTable = pcall(textutils.unserialise, credTable.contents)
                    -- Good luck.
                    if contentSuccess and message.saltProbe == contentTable.username then
                        BedrockNetworkServer.sendMessage(sender, {saltResponse = contentTable.salt or "error"}, protocol) -- respond. 4head.
                        return
                    end
                else
                    print("Failed to verify checksum!")
                end
            end
            BedrockNetworkServer.sendMessage(sender, {saltResponse = tostring(ecc.random.random())}, protocol) -- lie
        end)

        BedrockNetworkServer.addHandler("QueryDevices", function (sender, message, protocol)
            return clients[sender].userAuthed and type(message) == "table" and message.deviceQuery ~= nil
        end, function (sender, message, protocol)
            local deviceDescriptors = {}
            for i,v in pairs(devices) do
                local success, value = bedrockCore.GetSharedValue(tostring(v))
                if success then
                    deviceDescriptors[clients[v].clientID] = value
                end
            end

            deviceDescriptors.queryResult = true
            BedrockNetworkServer.sendMessage(sender, deviceDescriptors, protocol)
        end)

        BedrockNetworkServer.addHandler("DeviceMessage", function(sender, message, protocol)
            return clients[sender].userAuthed and type(message) == "table" and message.DeviceMessage == true
        end, function (sender, message, protocol)

            if type(message.deviceIDs) == "string" then
                local success, obj = pcall(textutils.unserialise, message.deviceIDs)
                if success then
                    message.deviceIDs = obj
                    for i,v in pairs(message.deviceIDs) do
                        if clients[v] ~= nil then
                            BedrockNetworkServer.sendMessage(v, {deviceRequest = true, fieldName = message.fieldName, params = message.params, type = message.type, user = sender}, protocol)
                        end
                    end
                end
            end
        end)

        BedrockNetworkServer.addHandler("MessageForwarder", function(sender, message, protocol)
            return type(message) == "table" and message.deviceResponse == true and message.routeTo ~= nil and clients[message.routeTo] ~= nil
        end, function(sender, message, protocol)
            -- God hates me 
            BedrockNetworkServer.sendMessage(message.routeTo, message.content, protocol)
            -- Every day I question why god hasn't smited me.
        end)

        BedrockNetworkServer.addHandler("DistributeFiredEvent", function (sender, message, protocol)
            return type(message) == "table" and message.eventFire == true and type(message.eventName) == "string"
        end,function (sender, message, protocol)
            for i,v in ipairs(users) do
                BedrockNetworkServer.sendMessage(v, message, endpointsLookup.encryptedMessageProtocol)
            end
        end)

        -- Has the ability to get all connected clients, but unlike the user version this one allows devices to deny discovery.
        BedrockNetworkServer.addHandler("InterDeviceRecordsRequest", function (sender, message, protocol)
            return type(message) == "table" and message.communicationRequestRecords == true
        end, function (sender, message, protocol)
            
        end)

        BedrockNetworkServer.addHandler("InterDeviceRecordResponse", function (sender, message, protocol)
            return type(message) == "table" and message.communicationRecordResponse == true and message.clientID and type(message.response) == "boolean"
        end, function (sender, message, protocol)
            if clients[sender].prospectivePeers[message.clientID] ~= nil then
                local cl = clients[sender].prospectivePeers[message.clientID]
                clients[sender].prospectivePeers[message.clientID] = nil
                -- If the response is positive then send the descriptor. Otherwise BAR THE REACTION >:(
                if message.response == true then
                    clients[sender].peers[message.clientID] = cl
                    BedrockNetworkServer.sendMessage(message.clientID, {recordResponse = true, recordAccepted = true, descriptor = bedrockCore.GetSharedValue(tostring(clients[sender].clientID))})
                else
                    clients[sender].rejectedPeers[message.clientID] = cl
                    BedrockNetworkServer.sendMessage(message.clientID, {recordResponse = true, recordAccepted = false})
                end
            end
        end)

        local function handleRequest(tdevices, sender)
            for i,v in pairs(tdevices) do
                if clients[i].rejectedPeers == nil then
                    clients[i].rejectedPeers = {}
                end
                
                -- Make sure we are NOT rejected.
                if clients[i].rejectedPeers[sender] == nil then
                    -- share our descriptor.
                    local deviceDescriptor = bedrockCore.GetSharedValue(tostring(clients[sender].clientID))
                    -- If we aren't add ourselves to the list of peers (in more ways than one) if accepted
                    clients[i].prospectivePeers[sender] = deviceDescriptor
                    BedrockNetworkServer.sendMessage(i, {peerRequest = true, rId = sender, cID = clients[sender].clientID, descriptor = deviceDescriptor}) -- Another handler will pick up where this left off. Blocking is bad
                end
            end
        end

        -- Some devices must communicate. Although they may not need to and due to their lower security imperitive they must make requests to avoid spam and whatnot.
        BedrockNetworkServer.addHandler("InterDeviceCommunicationRequest", function (sender, message, protocol)
            return type(message) == "table" and message.communicationRequestAction == true
        end, function (sender, message, protocol)
            --  act after checking if a category or device(s) are specified.
            local tdevices = {}
            if type(message.communicationCategory) == "string" then
                -- Consider other options for more efficient category dissemenation. Whatever. (hehe desemen)

                tdevices = {}

                -- So what do you call this strange p2p2p2p2p2p2p2god setup?

                -- Luckily this is a small network (typically) so this shouldn't kill everyone

                for i,v in pairs(clients) do
                    local peerDesc = textutils.unserialise(bedrockCore.GetSharedValue(tostring(clients[i].clientID)))
                    if type(peerDesc) == "table" and peerDesc.deviceType == message.communicationCategory then
                        tdevices[i] = v
                    end
                end

                handleRequest(tdevices, sender)
                -- but is is biggly creamy
            end

            if type(message.communicationDevices) == "table" or type(message.communicationDevices) == "number" then
                tdevices = message.communicationDevices
                local cDevices = {}
                if type(tdevices) == "number" then
                    tdevices = {[clients] = tdevices} -- Just turn it into a table, since it's just the singular form of devices.
                end

                for i,v in pairs(tdevices) do
                    if clients[v] ~= nil then
                        cDevices[v] = clients[v]
                    else
                        -- TODO: RESPOND. (or don't)
                    end
                end

                handleRequest(cDevices, sender)
            end
        end)

        -- This can be used to either terminate communication or establish it after a request.
        BedrockNetworkServer.addHandler("InterDeviceCommunicationStateModification", function (sender, message, protocol)
            return type(message) == "table" and message.communicationRecordResponse == true and type(message.clientrID) == "number" and type(message.response) == "boolean"
        end, function (sender, message, protocol)
                local cl = clients[message.clientrID]

                clients[message.clientrID].peers = nil
                clients[sender].peers[message.clientrID] = nil
                clients[sender].rejectedPeers[message.clientrID] = nil

                -- If the response is positive then send the descriptor. Otherwise BAR THE REACTION >:(
                if message.response == true then
                    if clients[sender].prospectivePeers[message.clientrID] ~= nil then
                        clients[sender].peers[message.clientrID] = cl
                        BedrockNetworkServer.sendMessage(message.clientrID, {recordResponse = true, recordAccepted = true, descriptor =  bedrockCore.GetSharedValue(tostring(clients[sender].clientID))})
                        clients[message.clientrID].peers = sender
                    else
                        clients[sender].rejectedPeers[message.clientrID] = nil
                    end
                else
                    clients[sender].rejectedPeers[message.clientrID] = cl
                    BedrockNetworkServer.sendMessage(message.clientrID, {recordResponse = true, recordAccepted = false})
                end

                clients[sender].prospectivePeers[message.clientrID] = nil
        end)


        BedrockNetworkServer.addHandler("InterDeviceCommunicationMessage", function (sender, message, protocol)
            return type(message) == "table" and message.clientrID ~= nil and clients[sender].peers[message.clientrID] ~= nil
            end, function (sender, message, protocol)
            
        end)

        BedrockNetworkServer.run()
        while true do
            os.sleep(0)
        end
    end

    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()