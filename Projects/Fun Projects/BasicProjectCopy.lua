    local bedrockCore = require("BedrockAPI.BedrockCore") -- Look I made the tool and it's useful. Stop judging me
    local bedrockInput = require("BedrockAPI.BedrockInput")
    local bedrockGraphics = require("BedrockAPI.BedrockGraphics")
    local BedrockNetworkDevice = require("BedrockAPI.BedrockNetworkDevice")
    local bedrockUI = require("BedrockAPI.BedrockUI")


    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new():addModule(BedrockNetworkDevice):addModule(bedrockInput):addModule(bedrockGraphics):addModule(bedrockUI)

    -- build your core so it'll be run in the update loop
    coreInstance:build()
    local loginState = "Logged Out"
    local loginStatePrev = nil
    local username = ""
    local password = ""

    local devices = {}
    local endpointsLookup = {}


    local monitor = bedrockInput.GetGenericDisplayPeripheral(term)
    local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)


    local menu = bedrockUI.menuBuilder:new(DOM):setBackgroundColor(colors.packRGB(term.nativePaletteColor(colors.black)))
    local loginMenu = nil
    local loginReady = false

    local commandMenu = {
        autoShow = {},
        theRest = {},
    }

    -- This needs better styling later. Whatever
    commandMenu.autoShow.commandTextBox = bedrockUI.textInputBuilder.new():setSize("100%", "3px"):setZ(1000):setY(14):setParent(menu):hide()
    commandMenu.autoShow.commandSubmit = bedrockUI.buttonBuilder.new():setSize("100%", "3px"):setZ(999):setY(18):setBackgroundColor("#23BD45"):setText("Send"):setParent(menu):hide()


    local loginReady = false

    local function submitCommand()
            local cmdStr = commandMenu.autoShow.commandTextBox.storedText
            local split = {}
            for str in string.gmatch(cmdStr, "%S+") do
                table.insert(split, str)
            end

            local matches = {}

            for i,v in pairs(devices) do
                for i2,v2 in pairs(v.functions) do
                    if i2 == string.lower(split[1]) then
                        table.insert(matches, i)
                        
                        break
                    end
                end
            end

            if #matches > 0 then
                local command = split[1]
                local commandTable = {
                    params = table.pack(table.unpack(split, 2, #split)),
                    DeviceMessage = true,
                    fieldName = string.lower(command),
                    type = "function",
                    deviceIDs = textutils.serialise(matches)
                }

                BedrockNetworkDevice.sendMessage(commandTable, false, endpointsLookup.encryptedMessageProtocol)
            end
    end

    commandMenu.autoShow.commandTextBox.onSubmit.addListener(submitCommand)

    local function submitLogin()
        if loginState == "Logged Out" then
            loginState = "Logging in"

            username = loginMenu.usernameTextBox.storedText
            password = loginMenu.passwordTextBox.storedText

            if (username == nil or username == "") and (password == nil or password == "") then
                return
            end

            loginMenu.submitButton:disable()
            loginMenu.usernameTextBox:disable()
            loginMenu.passwordTextBox:disable()


            local saltRequest = {
                saltProbe = string.lower(username)
            }

            loginState = "Awaiting Salt Response"

            BedrockNetworkDevice.sendMessage(saltRequest, false, endpointsLookup.encryptedMessageProtocol)
        end
    end

    commandMenu.autoShow.commandSubmit:addOnClick(submitCommand)

    local quitted = false

    local function quit(reasonCode)
        BedrockNetworkDevice.disconnect(reasonCode)
        quitted = true
    end

    bedrockInput.RegisterKeyEvent("terminate", function ()
            quit()
    end, function () end, function () end, nil, "grave")

    local function main()
        if loginMenu == nil then
            menu:setBackgroundColor(0xfcfcfc)
            loginMenu = {}
            loginMenu.usernameText = bedrockUI.menuObjectBuilder.new():setSize("100%", "1px"):setZ(1):setY(1):setTextColor("#10101f"):setText("Username:"):setParent(menu)
            loginMenu.usernameTextBox = bedrockUI.textInputBuilder.new():setSize("100%", "1px"):setZ(999):setY(3):setParent(menu)
            loginMenu.passwordText = bedrockUI.menuObjectBuilder.new():setSize("100%", "1px"):setZ(1):setY(5):setTextColor("#10101f"):setText("Password:"):setParent(menu)
            loginMenu.passwordTextBox = bedrockUI.textInputBuilder.new():setSize("100%", "1px"):setZ(999):setY(7):setParent(menu)

            loginMenu.submitButton = bedrockUI.buttonBuilder.new():setSize("100%", "3px"):setZ(999):setY(9):setBackgroundColor("#23BD45"):setText("Login"):setParent(menu)
            loginMenu.errorText = bedrockUI.menuObjectBuilder.new():setSize("100%", "10px"):setZ(1):setY(12):setTextColor("#E62A2A"):setText("ERROR TEXT"):setParent(menu):hide()
            loginMenu.errorText.gObject:setStyle("textAlign", "topleft")
            loginMenu.submitButton:addOnClick(submitLogin)
            loginMenu.passwordTextBox.onSubmit.addListener(submitLogin)
            loginMenu.usernameTextBox.onSubmit.addListener(submitLogin)
        end

        BedrockNetworkDevice.endpoints = {
            discoveryProtocol = "LabwareDeviceLookup",
            discoveryName = "LabwareServer",
            encryptedMessageProtocol = "LabwareMessage",
            messageACKProtocol = "LabwareMessageACK",
            callResponseProtocol = "LabwareCallResponse",
            authProtocol = "LabwareAuth",
            dns = "dns", -- This one is from CC itself, but consistency.
        }

        endpointsLookup = BedrockNetworkDevice.endpoints

        local returnToLoginMenu = function (hideErrorText)
            if loginMenu ~= nil then
                for i,v in pairs(loginMenu) do
                    v:show()
                end
            end
             
            if hideErrorText then
                loginMenu.errorText:hide()
            end
            loginMenu.passwordTextBox:enable()
            loginMenu.usernameTextBox:enable()
            loginMenu.submitButton:enable()

            for i,v in pairs(commandMenu) do
                for i2,v2 in pairs(v) do
                    v2:hide()
                end
            end
        end

        BedrockNetworkDevice.onDisconnect = function ()
            loginState = "Logged Out"
            returnToLoginMenu()
        end

        BedrockNetworkDevice.onConnect = function ()
            -- Uhhhh
        end

        -- Set to highest priority
        BedrockNetworkDevice.addHandler(function ()
            return true
        end, function ()
            loginStatePrev = loginState
        end, 9999999999)

        -- Set to lowest priority
        BedrockNetworkDevice.addHandler(function ()
            return true
        end, function (msg)
            -- If it is not in two defined states and has not been mutated since the last message
            if not (loginState == "Logged In" or loginState == "Logged Out") then
                if loginStatePrev == loginState then
                    loginState = "Logged Out"
                    
                    loginMenu.passwordTextBox:enable()
                    loginMenu.usernameTextBox:enable()
                    loginMenu.submitButton:enable()
                end
            end

            if type(msg) == "table" then
                if msg.deviceAttached then
                    if type(msg.descriptor) == "string" then
                        local descriptor = textutils.unserialise(msg.descriptor)
                        if descriptor ~= nil and msg.id ~= nil then
                            devices[msg.id] = descriptor
                        end
                    end
                elseif msg.deviceDetached then
                    if msg.id ~= nil then
                        devices[msg.id] = nil
                    end
                end
            end
        end, 0)

        BedrockNetworkDevice.addHandler(function ()
            return loginState == "Awaiting Salt Response"
        end, function(msg)
                local tableifiedMsg = {}
                tableifiedMsg.message = msg

                if type(tableifiedMsg) ~= "table" then
                    return
                end

                if type(tableifiedMsg) == "table" and type(tableifiedMsg.message) == "table" then
                    if type(tableifiedMsg.message.saltResponse) == "string" then
                        local authMessage = {
                            userLogin = true,
                            username = string.lower(username),
                            password = tostring(BedrockNetworkDevice.ecc.sha256.hmac(password, tableifiedMsg.message.saltResponse)),
                            salt = tableifiedMsg.message.saltResponse
                        }

                        -- NEVER keep keys in memory longer than needed.
                        username = ""
                        password = ""

                        os.sleep(0.25)

                        local authResponse = table
                        .pack(BedrockNetworkDevice.sendMessage(authMessage, false, endpointsLookup.encryptedMessageProtocol))
 
                        if authResponse[1] == true then
                            if authResponse[2] == nil or (type(authResponse[2]) == "table" and #authResponse[2] == 0) then
                                for i,v in pairs(loginMenu) do
                                    v:hide()
                                end

                                    os.sleep(0.25)

                                    local descriptorRequest = {
                                        deviceQuery = true
                                    }

                                    loginState = "Logged In"
                                    BedrockNetworkDevice.sendMessage(descriptorRequest, false, endpointsLookup.encryptedMessageProtocol)

                                    for i,v in pairs(commandMenu.autoShow) do
                                        v:show()
                                    end
                                else
                                    loginMenu.errorText:show()
                                    
                                    loginMenu.passwordTextBox:enable()
                                    loginMenu.usernameTextBox:enable()
                                    loginMenu.submitButton:enable()
                                    loginState = "Logged Out"
                                end
                        end
                    end
                end
        end)

        BedrockNetworkDevice.addHandler(function (msg)
            return type(msg) == "table" and msg.queryResult
        end, function (msg)
            local deviceDesc = msg

            for i,v in pairs(deviceDesc) do
                if type(v) == "string" then
                    local message = textutils.unserialise(v)
                    devices[i] = message or devices[i]
                end
            end
        end)

        BedrockNetworkDevice.addErrorHandler("setLoginErrorText", function ()
            return true -- Look I don't need a conditional here.
        end, function (msgObj)
            if msgObj.code ~= 007 then
                loginMenu.errorText:setText(string.format("[%s (%003i)]: %s", string.upper(msgObj.severity), msgObj.code, msgObj.errorMsg))
                if loginState == "Logged Out" then
                    loginMenu.errorText:show()
                end
            end
        end)
        
        returnToLoginMenu(true)

        BedrockNetworkDevice.run()

        returnToLoginMenu(false)

        --loginMenu.errorText:setText("[FATAL (100)]: Server Not Found"):show()

        loginMenu.submitButton:disable()


        while not quitted do
            os.sleep(0)
        end
        
    end

    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()