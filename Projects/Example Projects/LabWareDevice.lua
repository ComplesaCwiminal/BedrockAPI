---@diagnostic disable: cast-local-type

local configFile = "LabWareDevice.cfg"

local descriptorLocation
if fs.exists(configFile) then
    local fh = fs.open(configFile, "r")
    descriptorLocation = fh.readAll()
    fh.close()
else
    fs.open(configFile, "w").close()
    error(string.format("Missing config file! (%s) \nNote: The file has been created for you automatically, but is empty!", configFile), 0)
end

local deviceDescriptor = require(descriptorLocation)

local bedrockCore = require("BedrockAPI.BedrockCore") -- Look I made the tool and it's useful. Stop judging me
local bedrockInput = require("BedrockAPI.BedrockInput")
local ecc = require("Utils.ecc")

local modem = peripheral.find("modem", rednet.open)

local iteratorWindow = 10
local nonces = {}
local seenIters = {}
local errorNonces = {} -- Avoid replayed errors being treated as real.
local sharedSecret = nil

local serverKeyFile = "known_hosts.keys" -- named after SSH but with keys for parity with file format of the server.
local serverKey = nil
local fh = nil

local iter = 0
local id = 0

-- Max allowable is 30s this is in ms.
local heartBeatProperties = {
    min = 20000,
    max = 25000,
}

-- Always initialize your instance. Yes you need to. 
local coreInstance = bedrockCore.coreBuilder:new():addModule(bedrockInput):build()

local currentSession = 0

local errorcode = -1

local isInitted = false

-- Make sure this is mirrored on the server. Or in other words make sure you and your server are actually talking to eachother instead of a brick wall.
local endpointsLookup = {
    discoveryProtocol = "LabwareDeviceLookup",
    discoveryName = "LabwareServer",
    encryptedMessageProtocol = "LabwareMessage",
    messageACKProtocol = "LabwareMessageACK",
    callResponseProtocol = "LabwareCallResponse",
    authProtocol = "LabwareAuth",
    dns = "dns", -- This one is from CC itself, but consistency.
}

if fs.exists(serverKeyFile) then
    fh = fs.open(serverKeyFile, "r")
    local key = fh.readAll()
    local keyHashPair = textutils.unserialise(key)

    -- 
    if tostring(ecc.sha256.hmac(keyHashPair.key, "FUNNY ONE LINER")) == keyHashPair.hash then
        serverKey = {}
        for i = 1, #keyHashPair.key do
            table.insert(serverKey, string.byte(string.sub(keyHashPair.key, i,i)))
        end
    else
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
    end

    fh.close()
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
            print("Unable to deserialize message JSON. Likely malformed.")
            return false
        end

        if (premsg.iter <= iter - iteratorWindow or premsg.iter >= iter + iteratorWindow or seenIters[premsg.iter] ~= nil) then
            print("Noteworthy desync from client to server!" .. premsg.iter .. " / " .. iter .. "  " .. seenIters[premsg.iter])
            return false
        end

        if nonces[premsg.nonce] ~= nil then
            print("Duplicate Nonce!")
            return false
        end

        iter = (premsg.iter ~= nil and (premsg.iter > (iter or 0))) and premsg.iter + 1 or iter + 1
        nonces[premsg.nonce] = iteratorWindow * 2 + 5 -- Parity with the server.
        seenIters[premsg.iter] = iteratorWindow * 2 + 5

        for i,v in pairs(nonces) do
            nonces[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
        end

        for i,v in pairs(seenIters) do
            seenIters[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
        end
        
        -- If we don't fail then return the decrypted message and our new iterator
        return true, {message = msg}, iter
    else
        -- We know the message has no MAC, but we don't know why. (Errors are MACless.)
        print("MAC does not match message content. Possible tampering.")
        return false
    end

end

local function validateError(msgObj)
        -- Check if the message is from the server.
    -- The signature is created using the message so tampering with it should make signature verification fail. Also it has to be from our trusted server. duh.
    if msgObj.signature ~= nil and msgObj.message ~= nil and ecc.verify(serverKey, msgObj.message, msgObj.signature) then
        if errorNonces[msgObj.message.nonce] == nil and type(msgObj.message) == "table" and msgObj.message.isError then
            errorNonces[msgObj.message.nonce] = true
            print(string.format("[%s (%003i)]: %s", string.upper(msgObj.message.severity), msgObj.message.code, msgObj.message.errorMsg))

            if msgObj.message.sessionInvalid then
                return true, msgObj.message.errorMsg, msgObj.message.code
            end
        end
    end
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
    valid, ackMsg, newIter = validateMessage(response[2], iter - 1)
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
            print("Cannot validate or obtain acknowledgement!") -- We're confused
            return true, 001, "Unknown Auth Error"
        end
        rednet.send(id, {payload = msg, mac = tostring(mac)}, endpoint)
        response = table.pack(rednet.receive(nil, 3)) -- check for any ack. These are encrypted 
        
        if response ~= nil and #response > 0 then
            if response[3] == endpointsLookup.messageACKProtocol then
                valid, ackMsg, newIter = validateMessage(response[2], iter - 1)
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

local function main()
    while errorcode ~= 0 do
        id = rednet.lookup(endpointsLookup.discoveryProtocol, endpointsLookup.discoveryName)

        sharedSecret = nil
        seenIters = {}
        
        if id ~= nil then
            local chalID, challenge = rednet.receive(endpointsLookup.callResponseProtocol, 5.5)
            -- If we recieve another server's challenge. Ignore it, and wait for our own
            while chalID ~= id do
                if chalID == nil then
                    error("Timeout during initial challenge", 0)
                else
                    os.sleep(0)
                    chalID, challenge = rednet.receive(endpointsLookup.callResponseProtocol, 5.5)
                end
            end

            if serverKey == nil then
                fh = fs.open(serverKeyFile, "w")
                local storageTable = {
                    key = challenge.signatureKey,
                    hash = tostring(ecc.sha256.hmac(challenge.signatureKey, "FUNNY ONE LINER")) -- this isn't security this is for corruption detection
                }
                local serialized = textutils.serialise(storageTable)
                fh.write(serialized) -- Sent as a string
                serverKey = challenge.signatureKey
            else
                if not ecc.verify(serverKey, challenge.pubKey, challenge.signature) then
                    error("Server has invalid signature!", 0)
                end
            end

            local privateKey, publicKey = ecc.keypair(ecc.random.random())

            sharedSecret = ecc.exchange(privateKey, challenge.pubKey)

            os.sleep(.25) -- You aren't allowed to send messages too fast. You'll get denied. 

            rednet.send(id, {response = "Auth" .. challenge.sessionID, pubKey = publicKey}, endpointsLookup.authProtocol)

            local sendID = rednet.receive(endpointsLookup.authProtocol, 5.5) -- Contents don't matter. Just wait for this message from the right source.

            -- Cross talk management.
            while sendID ~= id and sendID ~= nil do
                sendID = rednet.receive(endpointsLookup.authProtocol, 5.5) -- Fun fact this usually just says auth success. We only care about that though because slow.
            end

            if sendID == nil then
                error("Timeout while waiting for auth completion!", 0)
            end

            iter = 0

            os.sleep(.25)

            local lastMsg = os.epoch("utc")

            parallel.waitForAny(function ()
                -- HEARTBEAT HALF
                -- This isn't security this is staggering to try and avoid DOS. (or the server doing DOS protection)
                local ranTime = heartBeatProperties.min

                while true do
                        os.sleep(0) -- sleep isn't always accurate as it's based on MC tick. ALWAYS check with a rt source like epoch
                        if os.epoch("utc") - lastMsg >= ranTime then
                        local success, invalid, _, code = sendMessage(ecc.random.random(), true, endpointsLookup.encryptedMessageProtocol)
                        if not success or invalid == true then
                            errorcode = code
                            os.sleep(1.5) -- Always back off a bit before retry. It could easily be a timing issue.
                            return
                        end
                        lastMsg = os.epoch("utc")
                        ranTime = math.random(heartBeatProperties.min, heartBeatProperties.max)
                        end
                end
            end, function ()
                -- MESSAGE RECIEVE HALF
                
                while true do
                    os.sleep(0) -- Sleep for one tick to make sure there aren't two modem ops in one tick.
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
                                    local tbMsg = {}
                                    tbMsg.message = textutils.unserialise(msg.message)
                                    msg = tbMsg.message
                                    
                                    iter = newIter
                                else
                                    print("Invalid Message!") -- Oh. 
                                end
                            else
                                local unknownMessage = msgEvent[2]
                                -- UNKNOWN PROTOCOL SENT TO US. Check it's not an error
                                if type(unknownMessage) == "table" then
                                    if validateError(msgObj) then
                                        return
                                    end
                                end
                            end
                        end
                    end
                    local res, msg, code = runMessageLoop()
                    if res ~= nil then
                        errorcode = code
                        os.sleep(1.5) -- Wait a bit before retry
                        return -- This allows quitting in the event of the server returning an error
                    end
                end
            end, function ()
            while errorcode ~= 0 do
                deviceDescriptor.main()
                os.sleep(0)
            end
            end)
        else
            error("Server not found? Reopen when theres a server to talk to.", 0)
        end
    end
end



bedrockInput.RegisterKeyEvent("terminate", function ()
    quit()
end, function () end, function () end, nil, "grave")
parallel.waitForAny(bedrockCore.Tick, main)

coreInstance:Cleanup()