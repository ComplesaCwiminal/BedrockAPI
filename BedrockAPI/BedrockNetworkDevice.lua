---@diagnostic disable: cast-local-type

local ecc = require("Utils.ecc")

local modem = peripheral.find("modem", rednet.open)

local iteratorWindow = 10
local nonces = {}
local seenIters = {}
local errorNonces = {} -- Avoid replayed errors being treated as real.
local sharedSecret = nil

local serverKey = nil
local fh = nil

local iter = 0
local id = 0

local endpointsLookup

local bedrockInput
local BedrockNetworkDevice = {}

local messageHandlers = {}
local errorHandlers = {}
local registeredErrors = 0

-- Max allowable is 30s this is in ms.
local heartBeatProperties = {
    min = 20000,
    max = 25000,
}

local coreInstance

local currentSession = 0

local function addHandler(prereq, callback, priority)
    local handler = {
        prereq = prereq,
        callback = callback,
        priority = priority or 9999
    }
    table.insert(messageHandlers, handler)
    table.sort(messageHandlers, function (a, b)
        return a.priority > b.priority
    end)
end

local function addErrorHandler(name, prereq, callback)
    local handler = {
        name = name,
        prereq = prereq,
        callback = callback,
    }

    if errorHandlers[name] == nil then
        errorHandlers[name] = handler
        registeredErrors = registeredErrors + 1
    end


    return true
end

local function removeErrorHandler(name)
    if errorHandlers[name] ~= nil then
        errorHandlers[name] = nil
        registeredErrors = registeredErrors - 1
        return true
    end
    return false, "No handler by given name!"
end

local function fireError(errorTbl)
    local anyObjections = false
    for i,v in pairs(errorHandlers) do
        if type(v) == "table" then
            --[[ Std format is as follows:
                {
                    message,
                    severity,
                    code (number),
                    extras (metadata)
                }
                This may be within a wrapper table telling you some other metadata or security stuff.
                Such as the following:
                - Session invalid?
                - Is this message an error?
                - Nonces

                Use the field isError to discern whether the standard format is within a wrapper table
            ]]
            
            if type(v.prereq) == "function" and type(v.callback) == "function" and v.prereq()  then
                local result = v.callback(errorTbl)
                anyObjections = not anyObjections and result or anyObjections
            end
        end
    end

    return anyObjections
end
local function validateMessage(msgObj)
    if msgObj == nil then
        return false
    end
        if tostring(ecc.sha256.hmac(msgObj.payload, sharedSecret)) == msgObj.mac then
            

        local premsg = textutils.unserialise(msgObj.payload) -- The message payload

        local msg = tostring(ecc.decrypt(premsg.message, sharedSecret)) -- Hey look. Easier. Thanks mt

        -- ACTUALLY HANDLE IT
        local success, tabledMsg = pcall(textutils.unserialise, msg)

        tabledMsg = tabledMsg ~= nil and tabledMsg or msg

        if not success or tabledMsg == nil then
            if BedrockNetworkDevice._DEBUG then
                print("Unable to deserialize message JSON. Likely malformed.")
            end
            return false
        end

        if (premsg.iter <= iter - iteratorWindow or premsg.iter >= iter + iteratorWindow or seenIters[premsg.iter] ~= nil) then
            if BedrockNetworkDevice._DEBUG then
                print("Noteworthy desync from client to server!" .. premsg.iter .. " / " .. iter .. "  " .. seenIters[premsg.iter])
            end
            return false
        end

        if nonces[premsg.nonce] ~= nil then
            if BedrockNetworkDevice._DEBUG then
                print("Duplicate Nonce!")
            end
            return false
        end

        iter = iter + 1

        nonces[premsg.nonce] = iteratorWindow * 2 + 5 -- Parity with the server.
        seenIters[premsg.iter] = iteratorWindow * 2 + 5

        for i,v in pairs(nonces) do
            nonces[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
        end

        for i,v in pairs(seenIters) do
            seenIters[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
        end

        -- If we don't fail then return the decrypted message and our new iterator
        return true, msg, iter
    else
        -- We know the message has no MAC, but we don't know why. (Errors are MACless.)
        if BedrockNetworkDevice._DEBUG then
        print("MAC does not match message content. Possible tampering.")
        end
        return false, {message = "Invalid MAC"}
    end

end

local function validateError(msgObj)
        -- Check if the message is from the server.
    -- The signature is created using the message so tampering with it should make signature verification fail. Also it has to be from our trusted server. duh.
    if msgObj.signature ~= nil and msgObj.message ~= nil and ecc.verify(serverKey, msgObj.message, msgObj.signature) then
        if errorNonces[msgObj.message.nonce] == nil and type(msgObj.message) == "table" and msgObj.message.isError then
            errorNonces[msgObj.message.nonce] = true

            fireError(msgObj.message)
            return true, msgObj.message.sessionInvalid, msgObj.message.errorMsg, msgObj.message.code
        end
    end
    return false
end

-- For encrypted messages.
local function sendMessage(message, isHeartbeat, endpoint)
    local queuedMessaged = {}
    iter = (iter or 0) + 1
    local messageTable = {iter = iter, nonce = ecc.random.random():toHex()}
    if isHeartbeat then
        messageTable.isHeartbeat = tostring(ecc.random.random())
    end
    messageTable.messageType = type(message)
    if message ~= nil then
        if type(message) == "table" then
            message = textutils.serialise(message)
        end

        messageTable.message = message
    end

    messageTable.message = ecc.encrypt(messageTable.message, sharedSecret)

    local msg = textutils.serialise(messageTable)

    local mac = ecc.sha256.hmac(msg, sharedSecret)
    
    rednet.send(id, {payload = msg, mac = tostring(mac)}, endpoint)

    local response = table.pack(rednet.receive(nil, 3)) -- check for any ack. These are encrypted 

    -- Wait for acknowledgement.
    local attempts = 0
    local maxAttempts = 5

    local valid, ackMsg, newIter
    if response[3] == endpointsLookup.messageACKProtocol then
        valid, ackMsg, newIter = validateMessage(response[2])
    else
        if type(response[2]) == "table" then
            local answer = table.pack(validateError(response[2]))
            if answer[1] == true then -- We can return early for errors
                return true, table.unpack(answer), queuedMessaged
            end
        end
        table.insert(queuedMessaged, response[2])
    end
    
    while #response == 0 or response == nil or not valid do
        attempts = attempts + 1
        if attempts > maxAttempts then
            if BedrockNetworkDevice._DEBUG then
                print("Cannot validate or obtain acknowledgement!") -- We're confused
            end
            return true, 001, "Unknown Auth Error"
        end
        rednet.send(id, {payload = msg, mac = tostring(mac)}, endpoint)
        
        response = table.pack(rednet.receive(nil, 3)) -- check for any ack. These are encrypted 
        
        if response ~= nil and #response > 0 then
            if response[3] == endpointsLookup.messageACKProtocol then
                valid, ackMsg, newIter = validateMessage(response[2])
            else
                if type(response[2]) == "table" then
                    return validateError(response[2])
                end
            end
        end
    end
    iter = newIter
    return true, queuedMessaged
end

local errorcode = nil
local function disconnect(reasonCode)
    reasonCode = reasonCode or 000
    if BedrockNetworkDevice.connected == true then
        BedrockNetworkDevice.sendMessage({disconnectRequest = true, reasonCode = reasonCode}, false, endpointsLookup.encryptedMessageProtocol)
        errorcode = 0
    else
        errorcode = 0
    end

    rednet.close()
end

local function run()
    endpointsLookup = BedrockNetworkDevice.endpoints
    -- You may not interact with these anymore after running.
    BedrockNetworkDevice.run = nil
    BedrockNetworkDevice.endpoints = nil

    if fs.exists(BedrockNetworkDevice.serverKeyFile) then
        fh = fs.open(BedrockNetworkDevice.serverKeyFile, "r")
        local key = fh.readAll()
        fh.close()

        local keyHashPair = textutils.unserialise(key)

        -- The hash is actually just a checksum. I called it this because I forgot that word
        if tostring(ecc.sha256.hmac(keyHashPair.key, "FUNNY ONE LINER")) == keyHashPair.hash then
            serverKey = {}
            for i = 1, #keyHashPair.key do
                table.insert(serverKey, string.byte(string.sub(keyHashPair.key, i,i)))
            end
        else
            if type(BedrockNetworkDevice.onKeyFailure) ~= "function" then
                -- If it doesn't match something's wrong.
                local response
                print("Your key is invalid or corrupted. Continue (Y/n)")
                while response ~= "y" and response ~= "n" do
                term.write("> ")
                response = string.lower(read())
                if response == "" then
                    response = "y"
                end
                end

                if response ~= "y" then
                    error("Cannot continue!", 0)
                end
            else
                if not BedrockNetworkDevice.onKeyFailure("KEYCORRUPTED", keyHashPair) then
                    return
                end
            end
        end

    end
    
    while errorcode ~= 0 do
        BedrockNetworkDevice.connected = false
        
        id = rednet.lookup(endpointsLookup.discoveryProtocol, endpointsLookup.discoveryName)

        sharedSecret = nil

        if id ~= nil then
            local chalID, challenge = rednet.receive(endpointsLookup.callResponseProtocol, 5.5)
            -- If we recieve another server's challenge. Ignore it, and wait for our own
            while chalID ~= id do
                if chalID == nil then
                    if registeredErrors < 1 then
                        error("Timeout during initial challenge", 0)
                    else

                        if fireError({code = 010, severity = "fatal", errorMsg = "Timeout During Initial Challenge"}) then
                            break -- We have to restart, but not neccisarily crash.
                        else
                            return false
                        end
                    end
                    else
                        os.sleep(0)
                        chalID, challenge = rednet.receive(endpointsLookup.callResponseProtocol, 5.5)
                    end
            end

            
            if type(challenge.body) ~= "string" then
                if fireError({code = 001, message = "Unknown Auth Error", severity = "error"}) then
                    break
                else
                    return false
                end
            end

            local contents = textutils.unserialise(challenge.body);
            if type(contents) ~= "table" then
                if fireError({code = 001, message = "Unknown Auth Error", severity = "error"}) then
                    break
                else
                    return false
                end
            end

            if type(contents.protocolVersion) ~= "string" or not BedrockCore.checkVersion(contents.protocolVersion, BedrockNetworkDevice.expectedServerVersion, BedrockNetworkDevice.versionCheckOperand) then
                if registeredErrors < 1 then
                    error("Servers version is Incompatible!", 0)
                else
                    if fireError({code = 300, severity = "fatal", errorMsg = "Incompatible Version"}) then
                        break -- We have to restart, but not neccisarily crash.
                    else
                        return false
                    end
                end
            end

            if serverKey == nil then
                fh = fs.open(BedrockNetworkDevice.serverKeyFile, "w")
                local storageTable = {
                    key = challenge.signatureKey,
                    hash = tostring(ecc.sha256.hmac(challenge.signatureKey, "FUNNY ONE LINER")) -- this isn't security this is for corruption detection
                }

                local serialized = textutils.serialise(storageTable)

                fh.write(serialized) -- Sent as a string
                serverKey = challenge.signatureKey
            else
                print(serverKey, contents.pubKey, challenge.signature)

                if not ecc.verify(serverKey, contents.pubKey, challenge.signature) then
                    if not BedrockNetworkDevice.onKeyFailure then
                        error("Server has invalid signature!", 0)
                    else
                        if not BedrockNetworkDevice.onKeyFailure("NOKEY") then
                            return
                        end
                    end
                end
            end

            local privateKey, publicKey = ecc.keypair(ecc.random.random())

            sharedSecret = ecc.exchange(privateKey, contents.pubKey)

            os.sleep(.25) -- You aren't allowed to send messages too fast. You'll get denied. 

            rednet.send(id, {response = "Auth" .. contents.sessionID, pubKey = publicKey}, endpointsLookup.authProtocol)

            local sendID = rednet.receive(endpointsLookup.authProtocol, 2) -- Contents don't matter. Just wait for this message from the right source.

            -- Cross talk management.
            while sendID ~= id and sendID ~= nil do
                sendID = rednet.receive(endpointsLookup.authProtocol, 2) -- Fun fact this usually just says auth success. We only care about that though because slow.
            end

            if sendID == nil then
                if registeredErrors < 1 then
                    error("Timeout while waiting for auth completion!", 0)
                else
                    if fireError({code = 011, severity = "fatal", errorMsg = "Timeout During Auth Flow"}) then
                        break -- We have to restart, but not neccisarily crash.
                    else
                        return false
                    end
                end
            end

            BedrockNetworkDevice.connected = true

            if type(BedrockNetworkDevice.onConnect) == "function" then
                BedrockNetworkDevice.onConnect()
            end

            iter = 0
            local lastMsg = os.epoch("utc")
            parallel.waitForAny(function ()
                -- HEARTBEAT HALF
                -- This isn't security this is staggering to try and avoid DOS. (or the server doing DOS protection)
                local ranTime = heartBeatProperties.min
                while true do
                        os.sleep(0) -- sleep isn't always accurate as it's based on MC tick. ALWAYS check with a rt source like epoch
                        if os.epoch("utc") - lastMsg >= ranTime then
                        local valid, errMsg, code = sendMessage(ecc.random.random(), true, endpointsLookup.encryptedMessageProtocol)
                        
                        if not valid then
                            return valid, errMsg, code
                        end

                        lastMsg = os.epoch("utc")
                        ranTime = math.random(heartBeatProperties.min, heartBeatProperties.max)
                        end
                end
            end, function ()
                -- MESSAGE RECIEVE HALF
                while true do
                    -- Wrapped in a function so I can return without breaking my parallel.
                    local function runMessageLoop()
                        local msgEvent = table.pack(rednet.receive()) -- No timeout since this is in parallel (and we never know when the server will respond.)
                        local msgObj = msgEvent[2]
                        local sender = msgEvent[1]
                        -- Ignore cross talk
                        if sender == id then
                            if msgEvent[3] == endpointsLookup.encryptedMessageProtocol then
                                local valid, msg, newIter = validateMessage(msgObj)
                                if valid then
                                    if type(msg) == "string" then
                                        local result = textutils.unserialise(msg)
                                        if result ~= nil then
                                            msg = result
                                        end
                                    end

                                    for i,v in ipairs(messageHandlers) do
                                        if v.prereq(msg) then
                                            v.callback(msg)
                                        end
                                    end

                                    iter = newIter
                                else
                                    if BedrockNetworkDevice._DEBUG then
                                        print("FAILED")
                                    end
                                end
                            else
                                local unknownMessage = msgEvent[2]
                                -- UNKNOWN PROTOCOL SENT TO US. Check it's not an error
                                if type(unknownMessage) == "table" then
                                    return validateError(msgObj)
                                end
                            end
                        end
                    end
                    local err, res, msg, code = runMessageLoop()
                    if err == true and res == true then
                        error(tostring(err) .. " " .. tostring(res) .. " " .. tostring(msg) .. " " .. tostring(code))
                        errorcode = code
                        os.sleep(1.5) -- Wait a bit before retry
                        return -- This allows quitting in the event of the server returning an error
                    end
                    os.sleep(0) -- Sleep for one tick to make sure there aren't two modem ops in one tick.
                end
            end, function ()
                while errorcode ~= 0 do
                    os.sleep(0)
                end
            end)

            if type(BedrockNetworkDevice.onDisconnect) == "function" then
                BedrockNetworkDevice.onDisconnect()
            end
        else
            if registeredErrors < 1 then
                error("Server not found? Reopen when theres a server to talk to.", 0)
            else
                if fireError({code = 100, severity = "fatal", errorMsg = "No Server found"}) then
                    break -- We have to restart, but not neccisarily crash.
                else
                    return false
                end
            end
        end
    end
end

local function init(modules, core)
    bedrockInput = modules.Input
    coreInstance = core
    -- Take any event
    coreInstance:registerEvent("", function (...)
        local args = {...}
        local concat = tostring(os.clock()) .. "|" .. tostring(os.epoch("utc"))

        for i,v in pairs(args) do
            concat = concat .. "|" .. tostring(v)
        end
        
        -- Feed it into the accumulator because yes
        ecc.random.seed(concat)
    end)
end

local function main()

end

local function cleanup()
    
end

BedrockNetworkDevice = {
    type = "BedrockModule",
    moduleDefinition = {
    Init = init,
    Main = main,
    Cleanup = cleanup,
    moduleName = "NetworkDevice",
    events = {
    },
    dependencies = {
        requirements = {
            {moduleName = "Core", version = "0.2.0", operand = ">="},
            {moduleName = "Input", version = "*"}
        },
        optional = {

        },
        conflicts = {

        }
    },
    version = "0.1.0"
    },
    ecc = ecc,

    heartBeatProperties = heartBeatProperties,
    serverKeyFile = "known_hosts.keys", -- named after SSH but with keys for parity with file format of the server.
    run = run,

    addHandler = addHandler,
    sendMessage = sendMessage,
    validateError = validateError,
    validateMessage = validateMessage,

    onConnect = nil,
    onDisconnect = nil,

    connected = false,
    disconnect = disconnect,

    _DEBUG = false,

    onKeyFailure = nil,

    addErrorHandler = addErrorHandler,
    removeErrorHandler = removeErrorHandler,

    expectedServerVersion = "0.2.0",
    versionCheckOperand = ">=",
}

-- Make sure this is mirrored on the server. Or in other words make sure you and your server are actually talking to eachother instead of a brick wall.
BedrockNetworkDevice.endpoints = {
    discoveryProtocol = "GenericSecureLookup",
    discoveryName = "Server",
    encryptedMessageProtocol = "SecureServerMessage",
    messageACKProtocol = "SecureServerMessageACK",
    callResponseProtocol = "CallResponse",
    authProtocol = "ServerAuth",
    dns = "dns", -- This one is from CC itself, but consistency.
}

endpointsLookup = BedrockNetworkDevice.endpoints

return BedrockNetworkDevice
