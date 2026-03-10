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
    local commandList = {
        devices = {
        }
    }

    local endpointsLookup = {}


    local monitor = bedrockInput.GetGenericDisplayPeripheral(term)
    local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)


    local menu = bedrockUI.menuBuilder:new(DOM):setBackgroundColor(colors.packRGB(term.nativePaletteColor(colors.black)))
    local loginMenu = nil

    local commandMenu = {
        autoShow = {},
        theRest = {},
    }

    -- What automatically shows up when you login
    local defaultTab = "term"
    local currentTab

    local commandsRegistered = 0
    local devicesRegistered = 0

    -- Little menus that hold functionalities.
    local tabs = {
        term = {
            autoShow = {}, theRest = {}
        },
        commands = {
            autoShow = {}, theRest = {}
        },
        dash = {
            autoShow = {}, theRest = {}},
        sched = {
            autoShow = {}, theRest = {}},
    }

    -- This needs better styling later. Whatever
    commandMenu.autoShow.commandTextBox = bedrockUI.textInputBuilder.new():setSize("100%", "3px"):setZ(1000):setY("eval(100% - 6px)"):setTextColor("#0F0C21"):setParent(menu):hide()
    commandMenu.autoShow.commandSubmit = bedrockUI.buttonBuilder.new():setSize("100%", "3px"):setZ(999):setY("eval(100% - 2px)"):setBackgroundColor("#23BD45"):setText("Send"):setParent(menu):hide()
    commandMenu.autoShow.headerBar = bedrockUI.menuObjectBuilder:new():setSize("100%", "1px"):setZ(999):setY(1):setBackgroundColor("#7F7F7F"):setParent(menu):hide()
    
    tabs.dash.autoShow.dashboardScroller = bedrockUI.scrollAreaBuilder:new():setSize("100%", "eval(100% - 1px)"):setY(2):setZ(5):setTextColor("#0F0C21"):setParent(menu):hide()
    tabs.dash.autoShow.Welcomer = bedrockUI.menuObjectBuilder:new():setSize("100%", "1px"):setText("Your LabWare Dashboard:"):setParent(tabs.dash.autoShow.dashboardScroller):hide()
    tabs.dash.autoShow.Welcomer.style.textAlign = "topleft"

    
    local connectedDeviceString = "There are %d devices connected"
    local commandsRegString = "for a total of %d commands"
    local automationsScheduledString = "There are %d automations currently tracked"
    tabs.dash.autoShow.connectedDevices = bedrockUI.menuObjectBuilder:new():setSize("100%", "1px"):setY(3):setText(string.format(connectedDeviceString, devicesRegistered)):setParent(tabs.dash.autoShow.dashboardScroller):hide()
    tabs.dash.autoShow.commandRegistered = bedrockUI.menuObjectBuilder:new():setSize("100%", "1px"):setY(4):setText(string.format(commandsRegString, commandsRegistered)):setParent(tabs.dash.autoShow.dashboardScroller):hide()
    tabs.dash.autoShow.scheduledTasks = bedrockUI.menuObjectBuilder:new():setSize("100%", "1px"):setY(6):setText(string.format(automationsScheduledString, 0)):setParent(tabs.dash.autoShow.dashboardScroller):hide()
    tabs.commands.autoShow.scrollArea = bedrockUI.scrollAreaBuilder:new():setSize("100%", "eval(100% - 1px)"):setY(2):setZ(5):setTextColor("#0F0C21"):setParent(menu):hide()

    local function refreshDashboard()
        tabs.dash.autoShow.connectedDevices:setText(string.format(connectedDeviceString, devicesRegistered))
        tabs.dash.autoShow.commandRegistered:setText(string.format(commandsRegString, commandsRegistered))
    end


    local cmdOffset = 1
    local cmdDeviceCache = {}
    local sectionObjects = {}
    local function refreshCommands()
        cmdOffset = 1
        for i,v in pairs(devices) do
            if cmdDeviceCache[i] == nil then
                local obj = bedrockUI.buttonBuilder:new():setSize("100%", "2px"):setY((cmdOffset * 2)):setZ(1055):setText(v.deviceName and v.deviceName .. " (" .. i ..")" or i):setParent(tabs.commands.autoShow.scrollArea):enable()
                term.setTextColor(colors.pink)
                print(obj)
                for i,v in pairs(obj) do
                    print(i,v)
                end
                obj:addOnClick(function ()
                    error("an error has occured")
                end)
                tabs.commands.autoShow["device_" .. tostring(i)] = obj
                obj.tag = "device_" .. tostring(i)
                cmdDeviceCache[i] = cmdOffset
                table.insert(sectionObjects, obj)

                cmdOffset = cmdOffset + 1
            end
        end

        for i,v in pairs(cmdDeviceCache) do
            if v ~= false then
                v = false
            else
                for i2 = v, #sectionObjects do
                    sectionObjects[i2]:setY(i2 - 1)
                end

                tabs.commands.autoShow[v.tag] = nil
                table.remove(sectionObjects, v)

                cmdOffset = cmdOffset - 1
                cmdDeviceCache[i] = nil
            end
        end
    end

    tabs.dash.refreshFunc = refreshDashboard
    tabs.commands.refreshFunc = refreshCommands

    -- That's very millisecond of you
    local timeBetweenRequisitions = 15000
 
    local lastrequisition = -1
    local function selectTab(tab)
        commandMenu.autoShow[currentTab]:setBackgroundColor("--semi-dark")
        -- Hide the old tab's content
        for i,v in pairs(tabs[currentTab].autoShow) do
            -- The header bar buttons have the same name as their category
                -- tabs[i] prevents the header bar buttons from being hidden
                    -- I was lazy
            if tabs[i] == nil and i ~= "headerBar" then
                v:hide()
            end
        end
        
        for i,v in pairs(tabs[currentTab].theRest) do
            v:hide()
        end

        currentTab = tab

        commandMenu.autoShow[currentTab]:setBackgroundColor("#ACACAC")

        if loginState == "Logged In" then

            if type(tabs[currentTab].refreshFunc) == "function" then
                tabs[currentTab].refreshFunc()
            end

            -- Show new tabs
            for i,v in pairs(tabs[currentTab].autoShow) do
                v:show()
            end

            if lastrequisition <= 0 or os.epoch("utc") - lastrequisition > timeBetweenRequisitions then

            local descriptorRequest = {
                deviceQuery = true
            }

            BedrockNetworkDevice.sendMessage(descriptorRequest, false, endpointsLookup.encryptedMessageProtocol)

            lastrequisition = os.epoch("utc")
            end
        end
    end

    local offset = 0

    for i,v in pairs(tabs) do
        commandMenu.autoShow[i] = bedrockUI.buttonBuilder:new():setSize(tostring(#i) .. "px" , "1px"):setX(tostring(1 + offset) .. "px"):setY(1):setZ(9999):setText(tostring(i)):setParent(menu):hide()
        commandMenu.autoShow[i]:addOnClick(function ()
           selectTab(i)
        end)
        offset = offset + #i + 1
    end
    currentTab = defaultTab
    

    selectTab(currentTab)

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
    commandMenu.autoShow.commandTextBox:enable()

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

    local function connectDevice(device, id)
        if type(device.functions) == "table" then
            
            if devices[id] == nil then
                devicesRegistered = devicesRegistered + 1
            end

            devices[id] = device

            -- Man I don't want to explain all this
            -- Basically I didn't want to go through removing extra indices from an update
            if commandList.devices[id] == nil then
                commandList.devices[id] = {}
            else
                commandsRegistered = commandsRegistered - commandList.devices[id].numCommands
            end

            commandList.devices[id].functions = {}
            commandList.devices[id].numCommands = 0

            for i2,v2 in pairs(device.functions) do
                commandsRegistered = commandsRegistered + 1
                commandList.devices[id].functions[i2] = v2
                commandList.devices[id].numCommands = commandList.devices[id].numCommands + 1 
            end

            refreshDashboard()
            refreshCommands()
        end
    end

    local function disconnectDevice(id)
        if devices[id] ~= nil then
            devicesRegistered = devicesRegistered - 1
            commandsRegistered = commandsRegistered - commandList.devices[id].numCommands

            commandList.devices[id] = nil
            refreshDashboard()
            refreshCommands()
        end
    end

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
            devices = {}
            devicesRegistered = 0
            commandsRegistered = 0

            if loginMenu ~= nil then
                for i,v in pairs(loginMenu) do
                    v:show()
                end
            end
             
            if hideErrorText then
                loginMenu.errorText:hide()
            end

            loginMenu.usernameTextBox.storedText = ""
            loginMenu.passwordTextBox.storedText = ""

            loginMenu.passwordTextBox:enable()
            loginMenu.usernameTextBox:enable()
            loginMenu.submitButton:enable()

            for i2,v2 in pairs(commandMenu.autoShow) do
                v2:hide()
            end

            for i3,v3 in pairs(commandMenu.theRest) do
                v3:hide()
            end

            for i,b in pairs(tabs) do
                for i2,v2 in pairs(b.autoShow) do
                    v2:hide()
                end

                for i3,v3 in pairs(b.theRest) do
                    v3:hide()
                end
            end
        end

        BedrockNetworkDevice.onDisconnect = function ()
            loginState = "Logged Out"
            loginMenu.errorText:setText("Server Disconnected")

            returnToLoginMenu()
        end

        BedrockNetworkDevice.onConnect = function ()
            returnToLoginMenu()
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
                            connectDevice(descriptor, msg.id)
                        end
                    end
                elseif msg.deviceDetached then
                    disconnectDevice(msg.id)
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

                                    os.sleep(0)

                                    local descriptorRequest = {
                                        deviceQuery = true
                                    }

                                    loginState = "Logged In"
                                    BedrockNetworkDevice.sendMessage(descriptorRequest, false, endpointsLookup.encryptedMessageProtocol)
                                    os.sleep(0)

                                    for i,v in pairs(commandMenu.autoShow) do
                                        v:show()
                                        v:enable()
                                    end
                                else
                                    loginMenu.errorText:setText("Login Error")

                                    returnToLoginMenu()

                                    loginState = "Logged Out"
                                end
                        end
                    end
                end
        end)

        BedrockNetworkDevice.addHandler(function (msg)
            return type(msg) == "table" and msg.queryResult ~= nil
        end, function (msg)
            local deviceDesc = msg

            for i,v in pairs(deviceDesc) do
                if type(v) == "string" then
                    local message = textutils.unserialise(v)
                    connectDevice(message, i)
                end
            end
        end)

        BedrockNetworkDevice.addErrorHandler("setLoginErrorText", function ()
            return true -- Look I don't need a conditional here.
        end, function (msgObj)
            if msgObj.code ~= 007 then
                loginMenu.errorText:setText(string.format("[%s (%003i)]: %s", string.upper(msgObj.severity), msgObj.code, msgObj.errorMsg))

                if loginState == "Logged Out" and msgObj.sessionInvalid then
                    returnToLoginMenu()
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

    tabs.term.autoShow = {}
    tabs.term.theRest = {}

    for i,v in pairs(commandMenu.autoShow) do
        tabs.term.autoShow[i] = v
    end

    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()