-- A cryptography lib. Holy crap.
-- I checked this things code. Half of the secure operations feed in more entropy if possible.
-- You know the rng seeds itself initially with like 10k random samples. I think my thing wasn't worth it. I just wanted funny rng.
local ecc = require("Utils.ecc")

-- We use no modules. We need only a very simple core.
local coreInstance

BedrockNetworkServer = {}
local bedrockCore

peripheral.find("modem", rednet.open)

local iteratorWindow = 10 -- This is plus or minus. Be aware.

local preservationModeTimer = nil

local onLockdown = false
local messagesGotten = 0

-- A list of IDs based off how much they've tried DOSing me. If you send too much you get blocked by an ever increasing amount.
local trustworthiness = {}

local nonEphemeralpubKey = nil
local nonEphemeralprivKey = nil
local fh = nil

local maxWidth = bit32 and 64 or 32 -- If the bit32 lib exist that means regular bit ops are 64 bit. In other words use 64 bit when available.

local disconnectActions = {}
local authActions = {}
local connectActions = {}

local endpointsLookup





local clients = {}

local nonces = {} -- Needs rename. This is just for logins to stop replayed logins from annoying clients, and to make sure both sides are communicating.

local handlers = {}
local function addHandler(Name, Precondition, Callback)
    local handler = {
        name = Name,
        precondition = Precondition,
        callback = Callback
    }

    if handlers[handler.name] == nil then
        handlers[handler.name] = handler
    else
        return false, "Handler by that name already exists!"
    end

    return handler
end

local function removeHandler(name)
    local didAnything = handlers[name] ~= nil
    handlers[name] = nil
    return didAnything
end

local function addDisconnectHandler(Name, Callback)
    local handler = {
        name = Name,
        callback = Callback
    }

    if disconnectActions[handler.name] == nil then
        disconnectActions[handler.name] = handler
    else
        return false, "Handler by that name already exists!"
    end

    return handler
end

local function removeDisconnectHandler(name)
    local didAnything = disconnectActions[name] ~= nil
    disconnectActions[name] = nil
    return didAnything
end
local function addConnectHandler(Name, Callback)
    local handler = {
        name = Name,
        callback = Callback
    }

    if connectActions[handler.name] == nil then
        connectActions[handler.name] = handler
    else
        return false, "Handler by that name already exists!"
    end

    return handler
end

local function removeConnectHandler(name)
    local didAnything = connectActions[name] ~= nil
    connectActions[name] = nil
    return didAnything
end

local function addAuthHandler(Name, Callback)
    local handler = {
        name = Name,
        callback = Callback
    }

    if authActions[handler.name] == nil then
        authActions[handler.name] = handler
    else
        return false, "Handler by that name already exists!"
    end

    return handler
end

local function removeAuthHandler(name)
    local didAnything = authActions[name] ~= nil
    authActions[name] = nil
    return didAnything
end

local function verifyMessage(sender, message)
    if type(message) ~= "table" or type(message.payload) ~= "string" or type(message.mac) ~= "string" then
        return
    end
    
    local pl = textutils.unserialise(message.payload)

    if type(pl) ~=  "table" then
        return
    end

    if pl.iter == nil or pl.nonce == nil or clients[sender].sessionID == nil or clients[sender].nonces[pl.nonce] ~= nil or pl.nonce == clients[sender].sessionID then
        print("Potential replay attack? Duplicate nonce from this session. Disregarding!")
        return
    end
    
    -- We allow slight desync, but not much
    if (clients[sender].lastMessageiter ~= nil and (pl.iter <= clients[sender].lastMessageiter - iteratorWindow or pl.iter >= clients[sender].lastMessageiter + iteratorWindow or clients[sender].seenIters[pl.iter] ~= nil)) then
        print("Nonce is not correct and/or is desynced. " .. clients[sender].lastMessageiter .. " / " .. pl.iter) -- The ever difficult dance of telling people what they need to know but not too much!
        return
    end

    -- how would the iter be nil. No idea. JIT bug? I guess.
    clients[sender].lastMessageiter = (pl.iter ~= nil and (pl.iter > (clients[sender].lastMessageiter or 0))) and pl.iter + 1 or clients[sender].lastMessageiter + 1
    -- make sure the nonces are outside the iter window. Just saying.
    clients[sender].nonces[pl.nonce] = iteratorWindow * 2 + 5 -- Double the iterator window + 5. Why +5? Arbitrary. 
    clients[sender].seenIters[pl.iter] = iteratorWindow * 2 + 5

    -- iterating through 25-26 unique keys is basically free (likely not timing attack viable because it only tells you that there are x nonces not anything about them. [so you can probably only tell vague age at best])
    for i,v in pairs(clients[sender].nonces) do
        clients[sender].nonces[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
    end
    
    for i,v in pairs(clients[sender].seenIters) do
        clients[sender].seenIters[i] = v - 1 > 0 and v - 1 or nil -- if it's lifespan elapses then remove it.
    end


    if tostring(ecc.sha256.hmac(message.payload, clients[sender].sharedSecret)) ~= message.mac then
        print("Message is malformed so mac check failed!")
        return
    end

    -- We need it as a byte array for decryption and table concat doesn't work with string.char.
    local themessage = tostring(ecc.decrypt(pl.message, clients[sender].sharedSecret))

    local success, tableifiedMessage = pcall(textutils.unserialise, themessage)

    if success == false or type(tableifiedMessage) ~= "table" then
        print("Message is malformed or decryption failed!")
        return
    end

    -- Just check if it's truthy (we use random values for heartbeat bodies so the message holds less consistency)
    if pl.isHeartbeat then
        clients[sender].onHeartbeat()
    end
    tableifiedMessage.messageType = pl.messageType
    return tableifiedMessage
end

local function sendMessage(reciever, message, protocol)
    if reciever == nil or clients[reciever] == nil or clients[reciever].isAuthenticated ~= true or clients[reciever].sharedSecret == nil then
        return false, "Client not registered, hasn't authed yet, and/or has no shared secret."
    end

    -- You know I'm not sure why but this fixes a nil reference in some edge cases. Probably related to the lack of locks in this language.
    local ss = clients[reciever].sharedSecret

    local messageType = type(message)
    -- If it's a table turn the payload into JSON.
    if messageType == "table" then
        local success, msg = pcall(textutils.serialise, message)

        if success then
            message = msg
        end
    end

    clients[reciever].lastMessageiter = (clients[reciever].lastMessageiter or 0) + 1

    local msg = textutils.serialise({iter = clients[reciever].lastMessageiter, nonce = ecc.random.random():toHex(), message = ecc.encrypt(tostring(message), ss), messageType = messageType})

    local mac = ecc.sha256.hmac(msg, ss)


    rednet.send(reciever, {mac = tostring(mac), payload = msg}, protocol)-- What a complex message. Luckily it's very structured.
end

local function generateError(code, persistSession)
    -- Most 0xx cat errors are fatal... Scalability? -- dw I changed that a bit
    -- 0xx category is client errors or information.
    -- 1xx category errors are server errors
    -- 2XX is protocol or expectation errors. Things like unsupported versions or things that can't be attributed to a failing of either side.
    -- Severity meaning:
    -- - Info: info; Self explanatory
    -- - Warning: will never kill connections but may change sec state
    -- - Error: An error, but may not kill the connection
    -- - Fatal: ALWAYS kill the connection. No matter what.
    local codeMessageLookup = {
        [000] = {message = "Safely disconnected!", severity = "info"}, -- This is the only 0xx error that isn't an error think 200 okay.
        [001] = {message = "Unknown Auth Error", severity = "error"}, -- We love this error because it's our 'fuck you you're being weird so I'm telling you nothing'
        [002] = {message = "Unsupported Protocol", severity = "error"},
        [003] = {message = "Invalid Client Authorization", severity = "fatal"},
        [004] = {message = "Heartbeat Timeout", severity = "fatal"},
        [005] = {message = "Tachycardia", severity = "fatal"},
        [006] = {message = "Invalid Session", severity = "fatal"}, -- Is it fatal? Technically not since this is thrown because you aren't connected.
        [007] = {message = "Sending Too Frequently", severity = "warning"}, -- I'm fatally scared of you. Quit that shit.
        [008] = {message = "Invalid Login", severity = "info"}, -- No idea what else the severity would be
        [009] = {message = "Invalid Action", severity = "warning"}, -- Yeah I have no idea what you're asking for.
        [010] = {message = "Timeout During Initial Challenge", severity = "fatal"}, -- Funnily enough we never fire 01X errors because they're used to know when IT can't reach US properly
        [011] = {message = "Timeout During Auth Flow", severity = "fatal"}, -- Oh and we don't use them because they leak too much info, but the client doesn't need to care about that.
        [100] = {message = "Server Not Found", severity = "fatal"}, -- So yeah we can't fire this error either because that would be an obvious lie
        [101] = {message = "Server Overloaded", severity = "warning"},
        [102] = {message = "Resource Not Found", severity = "error"},
        [200] = {message = "Incompatible Version", severity = "fatal"}, -- This one's a failing from either side so I didn't know where to put it
        [400] = {message = "Check the HTTP Version of This Error", severity = "chaos"}, -- Get it. Because it's a bad request.
        [401] = {message = "VERY Unauthorized", severity = "VERY fatal"},
        [404] = {message = "Wrong Universe", severity = "warning"}, -- I guess HTTP / HTTPS is another universe
    }

    local errorBody = {isError = true, code = code, errorMsg = (codeMessageLookup[code] ~= nil and codeMessageLookup[code].message or "Unknown Error; Unsupported Code"), severity = (codeMessageLookup[code] ~= nil and codeMessageLookup[code].severity or "unknown"), sessionInvalid = not persistSession, nonce = ecc.random.random()}

    return {message = errorBody, signature = ecc.sign(nonEphemeralprivKey, errorBody)}
end

-- Every client gets a nonce for initial setup. That nonce cannot be used again until the client disconnects.
local function getClient(ClientID, SessionID, msg)
    local client = {
        clientID = ClientID,
        sessionID = SessionID, -- We use this to avoid replay attacks just taking the whole client call/response. (This is also just a second factor)
        isAuthenticated = false,
        lastHeartbeat = nil,
        heartBeatInterval = BedrockNetworkServer.defaultHeartbeatTiming,
        nonces = {}, -- We'll use this after encryption to prevent replay attacks
        seenIters = {},
        lastMessageiter = nil,
        timer = nil
    }

    clients[ClientID] = client
    nonces[SessionID] = true
    client.disconnect = function (self, errorCode)
        local error = generateError(errorCode or 0)
        local errorReason = error.message.errorMsg
        print(string.format("Client Invalidated! \n%s (%003i)", errorReason, errorCode or 0), string.format("(%i)", client.clientID))
        -- Remove the prospective client from the database.
        
        clients[self.clientID] = nil
        nonces[self.sessionID] = nil

        self.timer:Cancel()
        self.timer = nil
        self.onHeartbeat = function () end
        self.disconnect = function () print(string.format("Already DC'd client (%i) tried to redisconnect", self.clientID)) end

        self.sharedSecret = nil -- This isn't strictly needed, but I mean it might make memory snooping harder.

        for i,v in pairs(disconnectActions) do
            if type(v.callback) == "function" then
                v.callback(client)
            end
        end

        if error ~= nil then
            rednet.send(self.clientID, error)
        end
    end

    -- If initial auth and heartbeat take more than 5 seconds. They autofail.
    _, client.timer = coreInstance:queueTimer(5000, function() client:disconnect(001) end)
    -- First auth also includes the first heartbeat being sent
    client.onFirstAuth = function ()
        -- We have successfully authed and heartbeat, so cancel that.
        client.timer:Cancel()
        client.isAuthenticated = true
        for i,v in pairs(authActions) do
            if type(v.callback) == "function" then
                v.callback(client)
            end
        end

        -- It's best if you send in your heartbeats rather early (but consistently) as to avoid network overhead issues
        _, client.timer = coreInstance:queueTimer(client.heartBeatInterval, function () client:disconnect(004) end)
    end

    -- Heartbeating has been changed to be more occasional. Network congestion was limiting concurrent clients.
    client.onHeartbeat = function()
        -- If it has been more than a second since the last heartbeat then allow it. otherwise it's a problem
        -- Me when heart attack of the tachycardia variety.
        local dt = os.epoch("utc") - client.lastHeartbeat
        if dt > 1000 then
        client.lastHeartbeat = os.epoch("utc")
        client.timer:Cancel()
        _, client.timer = coreInstance:queueTimer(client.heartBeatInterval, function () client:disconnect(004) end)
        else
            client:disconnect(005) -- If it too frequently heartbeats something is off. Heartbeats are once per 30 ish seconds by default.
        end
    end

    for i,v in pairs(connectActions) do
        if type(v.callback) == "function" then
            v.callback(client, msg)
        end
    end

    return client
end


-- Only use these 'nonces' as seeds or for low security services. This does make a fantastic seed for real rng algos tho.
-- Basic statistical testing of these sources leads me to a min entropy of about 26.1603872598 bits. Which is too low for crypto on it's own. However crypto ops are powered by a csprng which collects it's own so come to your own conclusion because I'm sorry I don't have one
-- Correlated sources were counted conservatively as to not fake results.
local function generateNonce()
        -- Yes I know math.random isn't cryptographically secure. If this weren't CC I'd replace it with a csprng. -- Dude shut up you are seeding a csprng with this you cannot feed randomness into itself.
        local epoch = os.epoch("utc")
        local ran = math.random(0, maxWidth)
        local ran2 = math.random(0, 0xFFFFFFFF)
        local atable = tostring({}) -- Table IDs are very very random. High randomness. You can thank CC's memory opaqueness for that.
        atable = tonumber(string.sub(atable, 8, #atable), 16)

        ran2 = bit.bxor(bit.brshift(ran2, atable), bit.blshift(ran2, maxWidth - atable))
        -- It's a time stamp we bit roll on a 'random' amount of places
        local nonce = bit.bxor(bit.bor(bit.brshift(epoch, ran), bit.blshift(epoch, maxWidth - ran)), ran2)
    


        while nonces[nonce] ~= nil do
            -- TODO make more secure nonce conflict algo.
            ran = math.random(0, maxWidth)
            nonce = bit.bxor(bit.bor(bit.brshift(epoch, ran), bit.blshift(epoch, maxWidth - ran)), ran2)
        end
        return nonce
end

os.sleep(0) -- This makes it more stable during multishell. No I don't know why but for some reason it is exponentially slower in multishell. (from less than 5 to around 40. god.)

-- When dealing with floats and small numbers remember to always do division (modulo) and mult because those tend to introduce high amounts of floating point imprecision. Which is entropy.
ecc.random.seed(ecc.sha256.hmac(generateNonce(), bit.bxor(math.floor((os.clock() % 1) * 1e16), ((math.sin(os.clock()) + math.cos(os.clock())) / math.pi) % 1 * 1e16)):toHex()) -- Look I get that the nonce generated isn't secure, but it's a great seed able to be made cheap
-- Why am I using what seems from my looking to be a real csprng for fake security? I dunno. Funny.
local function createTrustworthinessEntry(client)
    local tEntry = {
        recentMessages = 0, -- If they're in timeout don't reset this. Instead just lower it, and by less each time.
        recentTimeouts = 0, -- Bad dog. pissing on the floor
        inTimeout = false, -- Go to your room young man
        timeoutTimer = nil, -- Set this when someone goes into timeout
        timeOfLastPing = 0,
        timeOfThisPing = 0,
        decayLeft = 0,
    }

    return tEntry
end

local function handleTrustworthiness(client, weight)
    if trustworthiness[client] == nil then
        trustworthiness[client] = createTrustworthinessEntry(client)
    end
    local record = trustworthiness[client]

    record.timeOfLastPing = record.timeOfThisPing
    record.timeOfThisPing = os.epoch("utc")

    record.recentMessages = record.recentMessages + (weight or 1)
    -- this is starting to become a mouthful (a type-ful? I dunno it's long.)
    if record.recentMessages >= BedrockNetworkServer.singleClientMaxMessagesPerMin then
        if not record.inTimeout then
            record.recentTimeouts = record.recentTimeouts + 1
        end

        record.inTimeout = true
        record.decayLeft = BedrockNetworkServer.timeoutDecay

        --print((BedrockNetworkServer.singleClientMaxMessagesPerMin / (BedrockNetworkServer.penaltyDenominator * record.recentTimeouts)))

        local subtractor = math.floor(BedrockNetworkServer.singleClientMaxMessagesPerMin / (BedrockNetworkServer.penaltyDenominator * record.recentTimeouts))
        record.recentMessages = BedrockNetworkServer.singleClientMaxMessagesPerMin - subtractor > 0 and subtractor or 0

        if record.timeoutTimer ~= nil then
            -- Cancel the previous timer so you can't get out early
            record.timeoutTimer:Cancel()
        end

        -- queue a new timer in it's place
        _, record.timeoutTimer = coreInstance:queueTimer(BedrockNetworkServer.singleClientBlockTime + ((BedrockNetworkServer.blockTimeGrowth) ^ (BedrockNetworkServer.timeGrowthExponent * record.recentTimeouts)), function ()
            record.inTimeout = false
        end)
    else
        if record.recentTimeouts > 0 then
            record.decayLeft = record.decayLeft > 0 and record.decayLeft - 1 or 0

            if record.decayLeft == 0 and record.recentTimeouts > 0 then
                record.recentTimeouts = record.recentTimeouts - 1
                record.decayLeft = BedrockNetworkServer.timeoutDecay
            end
        end
    end

    trustworthiness[client] = record
end

-- This is your event handler for messages that pass auth logic. 
local function handleTrustedMessage(sender, message, protocol)
    local anyValid = false
    local toRun = {}
    local tbl = message -- parity with older version protocol
    for i,v in pairs(handlers) do
        if v.precondition(sender, tbl, protocol) then
            anyValid = true
            table.insert(toRun, function ()
                v.callback(sender, tbl, protocol)
            end)
        end
    end
    parallel.waitForAll(table.unpack(toRun)) -- parallelism is a boon in this env.
    return anyValid
end

local function parseLookup(_ev, sender, message, protocol)

    handleTrustworthiness(sender, BedrockNetworkServer.messageWeights.all)
    if trustworthiness[sender].inTimeout ~= true then
        -- This prevents a singular client from sending one really quick flood.
        if trustworthiness[sender].timeOfThisPing - trustworthiness[sender].timeOfLastPing >= BedrockNetworkServer.minimumGrouping then
            messagesGotten = messagesGotten + 1
            if messagesGotten > BedrockNetworkServer.maxMessagesPerMin then
                messagesGotten = math.floor(messagesGotten / 2) -- half it so that only continuous spam retriggers it, but also that we are less tolerant to continuous spam
                if preservationModeTimer ~= nil then
                    preservationModeTimer:Cancel()
                end
                preservationModeTimer = coreInstance:queueTimer(BedrockNetworkServer.preservationModeLength, function ()
                    preservationModeTimer = nil
                    onLockdown = false
                end)
            end

            if protocol == endpointsLookup.encryptedMessageProtocol then
                if clients[sender] ~= nil and clients[sender].isAuthenticated == true then
                    
                    local tableifiedMessage = verifyMessage(sender, message)

                    if tableifiedMessage == nil then
                        return
                    end

                    local didAction = false

                    if not onLockdown then
                        -- We have all the infra needed to do reordering, but nyi
                        handleTrustworthiness(sender, BedrockNetworkServer.messageWeights.action)
                        didAction = handleTrustedMessage(sender, tableifiedMessage, protocol)
                        os.sleep(0)
                    end

                        local ackmsg = "ACK" .. tostring(ecc.random.random())
                        ackmsg = string.sub(ackmsg, 1, math.floor(#ackmsg * (generateNonce() / (2^maxWidth)))) -- The nonce is just so it's harder to recognize data patterns. Completely irrelevent but it's so cheap and I love it so I wanted to use it again. (but I can't in real sec so it gets odd jobs.)
                        sendMessage(sender, ackmsg, endpointsLookup.messageACKProtocol)

                    if not didAction and not tableifiedMessage.isHeartbeat and not onLockdown then
                        -- Even an error is an acknowledgement of a kind.
                        rednet.send(sender, generateError(009, true), endpointsLookup.messageACKProtocol)
                    end
                    if onLockdown then
                        sendMessage(sender, generateError(101, true), endpointsLookup.encryptedMessageProtocol) -- Let them know so they don't try anything.
                    end
                else
                    print("Client is either not authed, or hasn't sent initial intent!" .. sender)
                    rednet.send(sender, generateError(006, false))
                end
            -- Check that this is a lookup
            elseif protocol == endpointsLookup.dns and type(message) == "table" and message.sProtocol == endpointsLookup.discoveryProtocol and not onLockdown then
                -- I think it's funny that the message is irrelevant here. Kind of.
                handleTrustworthiness(sender, BedrockNetworkServer.messageWeights.auth) -- This is to make auth spamming much less viable. Don't auth repeatedly.

                if not trustworthiness[sender].inTimeout then
                    print("Got new client!", sender)

                    if clients[sender] ~= nil then
                        print("Client is already registered? Disconnecting!")
                        clients[sender]:disconnect()
                    end

                    local sessionID = generateNonce() -- function needs a rename.

                    if nonces[sessionID] ~= nil then
                        print("ILLEGAL STATE! ID already exists in service?")
                        return
                    end

                    getClient(sender, sessionID, message)

                    print("Sending challenge!")
                    
                    -- Sometimes math breaks down and keypair generation fails. Not ideal but it's not a security issue
                    local privateKey, publicKey = ecc.keypair(ecc.random.random())
                    
                    clients[sender].privateKey = privateKey
                    clients[sender].publicKey = publicKey

                    os.sleep(0)
                    
                    local messageTbl = {body = textutils.serialise({sessionID = sessionID, pubKey = publicKey, protocolVersion = BedrockNetworkServer.moduleDefinition.version}), signatureKey = tostring(nonEphemeralpubKey)} 
                    messageTbl.signature = (ecc.sign(nonEphemeralprivKey, tostring(messageTbl.body)))
                    -- We check we get the sessionID back in one piece. That's it. This isn't the secure part so we're not worried about tamper protection, yet. Mostly corruption
                    rednet.send(sender, messageTbl, endpointsLookup.callResponseProtocol) -- After this transition into labware Auth
                    -- Do you think that this modules version and the protocol version are the same? Well that's future me's problem, but in theory they should be.
                    print("Sent!")
                else

                    rednet.send(sender, generateError(007, false))
                end
            elseif protocol == endpointsLookup.authProtocol and not onLockdown then
                if clients[sender] ~= nil and clients[sender].isAuthenticated == false then
                    if ("Auth" .. clients[sender].sessionID) ~= message.response then
                        clients[sender]:disconnect(001) -- Tampering or corruption occurred. This isn't for security just making sure both sides work to spec.    
                        return
                    end
                    clients[sender].sharedSecret = ecc.exchange(clients[sender].privateKey, message.pubKey)
                    clients[sender].lastHeartbeat = os.epoch("utc")
                    clients[sender].onFirstAuth()

                    print("Auth Completed.")
                    os.sleep(0)
                    rednet.send(sender, "Auth Success", endpointsLookup.authProtocol)
                else
                    -- I keep fat fingering the ~ key when typing !. I'm not removing it
                    print("Client is either already authed, or hasn't sent initial intent. Denying~!")
                    rednet.send(sender, generateError(001, true)) -- It's the first error I've thought of. I'm deciding now that 0xx category errors are client fault.
                end
            -- There are other protocols
            elseif onLockdown then
                print("Server is on lockdown!")
                rednet.send(sender, generateError(101, true))
            elseif protocol == endpointsLookup.messageACKProtocol then
                
            else
                print("Unknown Protocol!")
                rednet.send(sender, generateError(002, true))
            end
        else
            rednet.send(sender, generateError(007, false))
        end
    else
        os.sleep(0)
        --print("User in timeout and is not allowed to send right now!")
        rednet.send(sender, generateError(101, true))
    end
end
 
local monitor = peripheral.find("monitor")
-- Pretty but not required.

-- We have a better tool for making graphics (Bedrock Graphics), but I'm too lazy rn
local function decorativeSubservice()
    local lastTerm = term.current()
    term.redirect(monitor)
    term.clear()
    print()
    local numClients = 0
    for i,v in pairs(clients) do
        print(string.format("%s: %s, (Authed? %s)", i, v.sessionID, v.isAuthenticated))
        numClients = numClients + 1
    end
    term.setCursorPos(1,1)
    print("Connected Clients: ", numClients)
    term.redirect(lastTerm)
end

local repaintInterval = 5
local timeLeft = repaintInterval
local repaintManager
local repaintTimer = nil
repaintManager = function()
    local monX, monY = monitor.getSize()

    if timeLeft <= 0 then
        timeLeft = repaintInterval
        decorativeSubservice()
    end

    monitor.setCursorPos(1, monY)
    monitor.clearLine()
    monitor.write("Refresh in: " .. timeLeft)

    timeLeft = timeLeft - 1

    _, repaintTimer = coreInstance:queueTimer(1000, repaintManager)
end

local spamManager
local trustManager
local spamTimer = nil

-- TODO add drift to the calc for better precision
-- They call me cloudflare DDOS protection. No they don't
spamManager = function (drift)
    -- We can only sample a ms precision but if you want to allow over 1000 messages per minute then this allows that.
    local decrementAmount = BedrockNetworkServer.maxMessagesPerMin < 1000 and 1 or math.floor(BedrockNetworkServer.maxMessagesPerMin / 1000)
    if messagesGotten - decrementAmount > 0 then
        messagesGotten = messagesGotten - decrementAmount
    end
    spamTimer:Cancel()
    _, spamTimer = coreInstance:queueTimer(60000 / BedrockNetworkServer.maxMessagesPerMin, spamManager)
end

local lastsample = nil


local trustTimer = nil
trustManager = function (drift)
    local singleClientDecrement = BedrockNetworkServer.singleClientMaxMessagesPerMin < 1000 and 1 or math.floor(BedrockNetworkServer.singleClientMaxMessagesPerMin / 1000)

    for i,v in pairs(trustworthiness) do
        v.recentMessages = v.recentMessages - singleClientDecrement > 0 and v.recentMessages - singleClientDecrement or 0
    end

    lastsample = os.epoch("utc")
    trustTimer:Cancel()
    _, trustTimer = coreInstance:queueTimer(60000 / BedrockNetworkServer.singleClientMaxMessagesPerMin, trustManager)
end

local function main()

end

local function init(modules, core)
    bedrockCore = modules.Core
    coreInstance = core
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

local function cleanup()
    
end

local function run()

    if BedrockNetworkServer.messageWeights.thePurple ~= 1.92888 then
        error("error in thePurple subcoordinator service", 0)
    end

    endpointsLookup = BedrockNetworkServer.endpoints

    -- The labware discovery network
    rednet.host(endpointsLookup.discoveryProtocol, endpointsLookup.discoveryName)

    BedrockNetworkServer.endpoints = nil
    BedrockNetworkServer.run = nil

    -- Check for the file
    if fs.exists(BedrockNetworkServer.nEKeyFile) then
        fh = fs.open(BedrockNetworkServer.nEKeyFile, "r")
        local contents = fh.readAll()
        local message = textutils.unserialise(contents)
        -- I love checksumming.
        if tostring(ecc.sha256.hmac(message.keys, "1234")) == message.hash then
            local keys = textutils.unserialise(message.keys)
            nonEphemeralprivKey = keys.privKey
            nonEphemeralpubKey = keys.pubKey
        else
            error("Could not validate stored keys? Either corrupted or tampered with!", 0)
        end
    else
        nonEphemeralprivKey, nonEphemeralpubKey = ecc.keypair(ecc.random.random())
        fh = fs.open(BedrockNetworkServer.nEKeyFile, "w")
        local keysTable = {
            privKey = tostring(nonEphemeralprivKey),
            pubKey = tostring(nonEphemeralpubKey),
        }
        local serializedMSG = textutils.serialise(keysTable)
        local messageTable = {
            keys = serializedMSG,
            hash = tostring(ecc.sha256.hmac(serializedMSG, "1234")) -- This is not security it's corruption management. (or is it digornio)
        }

        fh.write(textutils.serialise(messageTable))
    end
    fh.close()

    coreInstance:registerEvent("rednet_message", parseLookup)
    _, spamTimer = coreInstance:queueTimer(60000 / BedrockNetworkServer.maxMessagesPerMin, spamManager)
    _, trustTimer = coreInstance:queueTimer(60000 / BedrockNetworkServer.singleClientMaxMessagesPerMin, trustManager)
    if monitor ~= nil then
    repaintManager()
    end
end

BedrockNetworkServer = {
    type = "BedrockModule",
    moduleDefinition = {
    Init = init,
    Main = main,
    Cleanup = cleanup,
    moduleName = "NetworkServer",
    events = {
    },
    dependencies = {
        requirements = {
            {moduleName = "Core", version = "*"},
        },
        optional = {

        },
        conflicts = {

        }
    },
    version = "0.3.0"
    },
    run = run,
    ecc = ecc,

    -- Implied endpoints table here. 
    clients = clients,

    nEKeyFile = "sign.key",

    preservationModeLength = 30000,
    singleClientMaxMessagesPerMin = 72, -- This is a maximum. It'll never let you have more than this
    singleClientBlockTime = 15000, -- 15 seconds
    blockTimeGrowth = 2500,
    timeGrowthExponent = 1.25, -- means it grows by blockTimeGrowth to the timeGrowthExponent power
    timeoutDecay = 250, -- Normal messages for one timeout record to decay
    penaltyDenominator = 2, -- Basically how quick it nukes your ability to speak without trust. 2 would be a halving of messages allowed after each timeout.
    minimumGrouping = 150, -- Minimum time difference that a single client can send two pings
    defaultHeartbeatTiming = 45000,
    maxMessagesPerMin = 250,

    -- Valid Message Handlers
    addHandler = addHandler,
    removeHandler = removeHandler,

    -- Client Connection Handlers
    addDisconnectHandler = addDisconnectHandler,
    removeDisconnectHandler = removeDisconnectHandler,
    
    addConnectHandler = addConnectHandler,
    removeConnectHandler = removeConnectHandler,

    -- Message parsing, and trustworthiness
    sendMessage = sendMessage,
    verifyMessage = verifyMessage, -- These two aren't commonly used on the server side but they're invaluble when you do need them.
    handleTrustworthiness = handleTrustworthiness, -- Used to apply the weights as defined above.

    generateError = generateError,
}

BedrockNetworkServer.endpoints = {
    discoveryProtocol = "GenericSecureLookup",
    discoveryName = "Server",
    encryptedMessageProtocol = "SecureServerMessage",
    messageACKProtocol = "SecureServerMessageACK",
    callResponseProtocol = "CallResponse",
    authProtocol = "ServerAuth",
    dns = "dns", -- This one is from CC itself, but consistency.
}

-- Message weights add to each other. So all messages get 'all' and then may get auth or action or whatever.
BedrockNetworkServer.messageWeights = {
    all = 1,
    auth = 12, -- Auth is expensive okay?
    thePurple = 1.92888, -- oh
    action = 2,
    protectedQuery = 4,
}

return BedrockNetworkServer