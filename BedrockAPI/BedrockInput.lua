 --[[+----------------------------------------------------------+
    |                      I/O MODULE                          |
    |                    +------------+                        |
    | What this module handles: Keyboard, mouse, peripherals,  |
    |                      Description:                        |
    | This module is designed to handle all human facing parts |
    |            of the computercraft experience.              |
    +----------------------------------------------------------+
---------------------------------------------------------------]]
local BedrockInput = {}
-- Core module is needed to manage the resize events of display peripherals
local coreModule = nil

-- The current keysheld
local _keysHeld = {}
-- The current registered KEY ONLY events
local registeredKeyEvents = {}
local debugItems = {
    -- the debug device can be either a monitor or a debugger (if they exist)
    debugDevice = nil,
    debugMode = false,
    debugLogging = {
        enabled = false,
        maxLinesShown = 5,
        loggingCategories = {},

    },
}

--[[+---------------------+
----| PERIPHERALS SECTION |
--------------------------+]]

-- Note: devices holds all devices that have EVER been attached, regardless of if they are now disconnected
-- Use this to notice when a device is unplugged, but is then gotten back (I guess I'll do the same...)
-- This is global by design. Obviously. We need it to have a shared state for peripherals 
if _G.peripheralManager == nil then
    _G.peripheralManager = {
        devices = {},
        connectedDevices = {},
        connectedDevicesUnsorted = {},
        activeDevices = 0,
    }
end

local function isPeripheralTypeConnected(pType) 
    if type(pType) == "string" then
        return not (_G.peripheralManager.connectedDevices[pType])
    elseif (type(pType) == "table" and not (pType.base == nil)) then
        return not (_G.peripheralManager.connectedDevices[pType.base.type] == nil)
    end
    error("Given object is not a Peripheral or a side:  \n" .. pType)
end

-- registers ALL attached peripherals
local function registerAllPeripherals()
    _G.peripheralManager.devices = {}
    _G.peripheralManager.connectedDevices = {}
    _G.peripheralManager.connectedDevicesUnsorted = {}
    _G.peripheralManager.activeDevices = 0
    
    for i,v in pairs(peripheral.getNames()) do
        AddPeripheral(BedrockInput.GetPeripheralFromText(v))
    end
end

local function onPeripheralConnect(_ev, side)
    local peripheralObj = BedrockInput.GetPeripheralFromText(side)
    if _G.peripheralManager.devices[peripheralObj.base.type] ~= nil and _G.peripheralManager.devices[peripheralObj.base.name] then
        
    end
    AddPeripheral(peripheralObj) 
end


 function AddPeripheral(peripheralObj) 

    if (_G.peripheralManager.devices[peripheralObj.base.type] == nil) and ((not type(_G.peripheralManager.devices[peripheralObj.base.type]) == "table")) then
        _G.peripheralManager.connectedDevices = {}
    end
    
    peripheralObj.isConnected = true
    _G.peripheralManager.devices[peripheralObj.base.name] = peripheralObj
    if _G.peripheralManager.connectedDevices[peripheralObj.base.type] == nil then
        _G.peripheralManager.connectedDevices[peripheralObj.base.type] = {}
    end
    _G.peripheralManager.connectedDevices[peripheralObj.base.type][peripheralObj.base.name] = peripheralObj
    _G.peripheralManager.connectedDevicesUnsorted[peripheralObj.base.name] = peripheralObj
    _G.peripheralManager.activeDevices = _G.peripheralManager.activeDevices + 1
end

local function onPeripheralDetach(_ev, side)
    --error("!")
    for i,v in pairs(_G.peripheralManager.connectedDevicesUnsorted) do
        if v.base.side == side then

            _G.peripheralManager.devices[v.base.type][v.base.name].base.hooks.onDisconnect()
            --_G.peripheralManager.devices["term"]["term"].base.hooks.onDisconnect()


            v.isConnected = false
            _G.peripheralManager.connectedDevices[v.base.type][v.base.name] = nil
            _G.peripheralManager.connectedDevicesUnsorted[v.base.name] = nil
            _G.peripheralManager.activeDevices = _G.peripheralManager.activeDevices - 1
        end
    end

end

local function getPeripheralFromText(side)
    -- Get the peripheral from the peripheral.wrap, using the defined side
    local result = BedrockInput.GetPeripheralFromObject(peripheral.wrap(side))
    return result
end

local function getPeripheralByType()

end

--- Uses a wrapped peripheral to get 
--- @param Obj peripheral # The WRAPPED object gotten from peripheral.wrap
local function getPeripheralFromObject(Obj)
    -- Get the generic peripheral, which provides a constant raw interface to any peripheral
    local genericBase = GetGenericPeripheral(Obj) 

    local peripheralType = genericBase.type
    if peripheralType == "computer" then
    
        return GetComputer(genericBase, Obj)
    elseif peripheralType == "drive" then

        return GetDrivePeripheral(genericBase, Obj)

    elseif peripheralType == "modem" then
        return GetModem(genericBase, Obj)

    elseif peripheralType == "printer" then
    
        return GetPrinter(genericBase, Obj)
    elseif peripheralType == "speaker" then
    
        return GetSpeaker(genericBase, Obj)
    elseif peripheralType == "monitor" then

        return GetMonitor(genericBase, Obj)
    end
    
    return genericBase
end

function GetGenericPeripheral(peripheralObject)
    local peripheralObj = {
        base = {
        isConnected = true,
        functions = peripheralObject,
        terminal = false
        }
    }
        local periphMeta = getmetatable(peripheralObject)

        -- If it has no metatable, then it's a term or redirect. God I wish this behavior was documented.
        if periphMeta == nil then
            -- A sensible enough default. I am scared.
            peripheralObj.base.type = "term"
            peripheralObj.base.name = "0"



            -- If we got here we're a terminal of some kind
            peripheralObj.base.terminal = true

            -- Set whatever was wrapped to the functions list.
            peripheralObj.base.functions = peripheralObject

            local current = term.current()
            -- Assuming that this is a peripheral it'll have a metatable
            local currentMeta = getmetatable(current)

            -- If we are a redirect then set the original values to the currents.
            if currentMeta ~= nil and currentMeta.__name == "peripheral" then
                peripheralObject = current
                periphMeta = currentMeta
            end
        end


        if periphMeta ~= nil then
            peripheralObj.base.type = peripheral.getType(peripheralObject) 
            peripheralObj.base.name = peripheral.getName(peripheralObject)
        end
        

    -- No Lua, coreModule cannot be nil, and if it is than we're all screwed anyway.

    -- The object has to exist before you get here so it's too late for on connect
    -- This'll be used in some places to try and scale screens after reconnection. Fun fact
    coreModule:createHook(peripheralObj.base, "onDisconnect", "string"):createHook(peripheralObj.base, "onReconnect", "string")
    
    if _G.peripheralManager.connectedDevices[peripheralObj.base.type] == nil or _G.peripheralManager.connectedDevices[peripheralObj.base.type][peripheralObj.base.name] == nil then
        if _G.peripheralManager.connectedDevices[peripheralObj.base.type] == nil then 
            _G.peripheralManager.connectedDevices[peripheralObj.base.type] = {}
        end

        _G.peripheralManager.connectedDevices[peripheralObj.base.type][peripheralObj.base.name] = peripheralObj

        return peripheralObj
    else
        return _G.peripheralManager.connectedDevices[peripheralObj.base.type][peripheralObj.base.name]
    end
end
local function getGenericDisplayPeripheral(object)
    assert(type(object) == "table", "Provided object is not a peripheral! (" .. type(object) .. ")")

    local genericPeripheral = GetGenericPeripheral(object)

    -- Should've given it it's own var, but it was in my clipboard.
    if _G.peripheralManager.connectedDevices[genericPeripheral.base.type][genericPeripheral.base.name].generic ~= nil then
        return _G.peripheralManager.connectedDevices[genericPeripheral.base.type][genericPeripheral.base.name].generic
    end
    assert(genericPeripheral.base.functions.write ~= nil, "Object isn't a display out.", 0)
    local displayPeripheral = {
        generic = object,
        base = genericPeripheral.base,
        colorsInUse = {},
        colors = {},
        functions = object,
        clear = nil,
        buffers = {}
    }

    coreModule:createHook(displayPeripheral, "onResize", "number", "number")
    displayPeripheral.onResize = function(ev, ourDisplay, display)
        if display == ourDisplay.base.name then
            displayPeripheral.hooks.onResize(ourDisplay.generic.getSize())
            ourDisplay.width, ourDisplay.height = (ourDisplay.generic.getSize or ourDisplay.generic.getPageSize)()
            displayPeripheral.buffers[1].reposition(1, 1, ourDisplay.width, ourDisplay.height)
            displayPeripheral.buffers[2].reposition(1, 1, ourDisplay.width, ourDisplay.height)
        else 
            -- Not it!
        end
    end
    --While you can pretend a printer is a screen. Stop that.
    if displayPeripheral.base.type == "printer" then
        
        local newPage = object.newPage()
        displayPeripheral.generic.newPage = function ()
            displayPeripheral.pageStarted = newPage
            return displayPeripheral.pageStarted
        end
        -- start a new page
        -- Probably replace these with a non erroring version.
        if not object.newPage() then
            if object.getInkLevel() <= 0 then
                error("OUT OF INK.", 0)
            end
            if object.getPaperLevel() <= 0 then
                
                error("OUT OF PAPER.", 0)
            end
        end
        displayPeripheral.clear = function () object.endPage() object.newPage()end
        displayPeripheral.generic.isColor = function ()
            return false
        end
        displayPeripheral.generic.isColour = function ()
            return false
        end
        displayPeripheral.generic.getSize = function ()
            if displayPeripheral.pageStarted then
                return object.getPageSize()
            else
                return 1, 1
            end
        end

        displayPeripheral.generic.scroll = function (y)
            if y ~= 1 then
                error("Printers cannot scroll. I'm sorry man (Scrolled: " .. y .. " units)", 0)
            end
        end
    else 
        displayPeripheral.clear = object.clear
    end

    displayPeripheral.width, displayPeripheral.height = object.getSize()
    
    displayPeripheral.buffers[1] = window.create(object ~= term and object or object.current(), 1, 1, displayPeripheral.width, displayPeripheral.height, true)
    displayPeripheral.buffers[2] = window.create(object ~= term and object or object.current(), 1, 1, displayPeripheral.width, displayPeripheral.height, false)

    if object.getBackgroundColour ~= nil then
        displayPeripheral.backgroundColor = object.getBackgroundColour()
    end    if object.getTextColor ~= nil then
        displayPeripheral.textColorColor = object.getTextColor()
    end

    if displayPeripheral.base.type == "term" then
        coreModule:registerEvent("term_resize", function(ev, display) displayPeripheral.onResize(ev, displayPeripheral, "term") end)
    else
        coreModule:registerEvent("monitor_resize", function(ev, display) displayPeripheral.onResize(ev, displayPeripheral, display) end)
    end

    _G.peripheralManager.connectedDevices[displayPeripheral.base.type][displayPeripheral.base.name].generic = displayPeripheral --Circular? Yes. Be aware

    return displayPeripheral
end

--- @class monitor monitor
--- @field getSize fun(): number, number
--- @param genericObject table the generic object version of the peripheral
--- @param object monitor the wrapped version of the peripheral
--- @return table monitor the monitor object
function GetMonitor(genericObject, object)
    local monitorObj = {
        generic = object,
        base = genericObject.base,
        backgroundColor = object.getBackgroundColor(),
        textColor = object.getTextColor(),
        colors = {}, 
        colorsInUse = {},
        onResize = function() end,
        buffers = {}
    }
    monitorObj.width, monitorObj.height = object.getSize()
        monitorObj.onResize = function(ev, ourDisplay, display)
        if display == ourDisplay.base.name then
            monitorObj.hooks.onResize(ourDisplay.generic.getSize())
            ourDisplay.width, ourDisplay.height = ourDisplay.generic.getSize()
            monitorObj.buffers[1].reposition(1, 1, ourDisplay.width, ourDisplay.height)
            monitorObj.buffers[2].reposition(1, 1, ourDisplay.width, ourDisplay.height)
        else 
            -- Not it!
        end
    end
    return monitorObj
end

function GetSpeaker(genericObject, object)
    local speakerObj = {
        generic = object,
        base = genericObject.base,
        maxVolume = 100,
        volume = 100,
        tracks = {}, -- Up to 8 tracks can play at once, (Actually it's 8 per 1/20th of a second. Good luck with that math)
        loadedStream = nil, -- Supports amplitudes from -128 to 127, played back at 48kHz. Buffer is about 128x1024 samples. Supports 8-bit pcm audio, but reencodes it. L
        
    }
    return speakerObj
end

function GetModem(genericObject, object)
    local modemObj = {
        generic = object,
        base = genericObject.base,
        isWireless = object.isWireless(),
        openChannels = {},
        openChannelCount = 0,
    }   
    return modemObj
end

function GetPrinter(genericObject, object)
    local printerObj = {
        generic = object,
        base = genericObject.base,
        pageTitle = "",
        paperWidth, paperHeight = object.getPaperSize(),
        paperLevel = object.getPaperLevel(),
        inkLevel = object.getInkLevel(),
    }

    return printerObj
end

function GetDrivePeripheral(genericObject, object)
    local drivePeripheralObj = {
        generic = object,
        base = genericObject.base,
        diskInserted = object.isDiskPresent(),
        diskID = object.getDiskID(),
        mountPath = object.getMountPath(),
    }
    return drivePeripheralObj
end

function GetComputer(genericObject, object)
    local computerObj = {
        generic = object,
        base = genericObject.base,
        computerID = object.getID(),
        isOn = object.isOn(),
    }
    return computerObj
end

--[[+------------------+
    | KEYBOARD SECTION |
    +------------------+]]
    
local eventsHeld = {}
local nextID = 1

-- Registers a key event, keys for event requires ALL keys in it to be down for it to fire
local function registerKeyEvent(EventName, PressEventEffect, HeldEventEffect, ReleaseEventEffect, KeyboardStyle, KeysForEvent, ...)
    -- Define the structure for a key event

    local keyEvent = {
        eventName = (type(EventName) == "string" and EventName) or nil,
        eventID = (registeredKeyEvents == nil and 1) or #registeredKeyEvents,
        pressEventEffect = (type(PressEventEffect) == "function" and PressEventEffect) or nil,
        heldEventEffect = (type(HeldEventEffect) == "function" and HeldEventEffect) or nil,
        releaseEventEffect = (type(ReleaseEventEffect) == "function" and ReleaseEventEffect) or nil,
        keysForEvent = (type(KeysForEvent) == "table" and KeysForEvent) or {},  
        keyboardStyle = type(KeyboardStyle) == "boolean" and KeyboardStyle or true, -- Basically whether the hold should be per frame or should be treated like a typing input or if it'll fire every frame after being hit
        keysHeld = {},
        requirementsMet = false
    }
    if type(KeyboardStyle) ~= "boolean" then
        table.insert(keyEvent.keysForEvent, 1, KeyboardStyle)
    end
    -- If there aren't more than one key, then KeysForEvent will just be a string
    -- This will also be true if they're given as individual strings. eg. "a","b","c" 
    -- That is considered bad practice here, though.
    if type(KeysForEvent) == "string" then
    -- In that case, just add it to the object anyway
        table.insert(keyEvent.keysForEvent, KeysForEvent)
    end

    -- Extra code to handle being given a group of individual strings, as to not lose info
    local extras = {...}

    -- extra should usually be nil, but if not
    if not (extras == nil) then
        -- add all the strings to the keyevent as keys.
        for i,v in ipairs(extras) do
            if type(v) == "string" then
                table.insert(keyEvent.keysForEvent, v)
            end
        end
    end

    if not (keyEvent.keysForEvent == nil) then
        for i,v in pairs(keyEvent.keysForEvent) do
            keyEvent.keysHeld[v] = false
        end 
    end
    
    -- If the event name is nil
    if keyEvent.eventName == nil then
        -- Use fallback event registration
        table.insert(registeredKeyEvents, keyEvent)
    else 
        -- Otherwise use the normal event registration,
        -- Registers events into the table by their name for easier destruction later

        -- If there are no keys registered into that slot
        if registeredKeyEvents[keyEvent.eventName] == nil then
            -- Make sure it's a table so we can use table.insert
            registeredKeyEvents[keyEvent.eventName] = {}
        end
        -- insert it into the table so we don't overwrite keyEvents if they have the same name.
        table.insert(registeredKeyEvents[keyEvent.eventName], keyEvent)
    end
    
    return keyEvent, #registeredKeyEvents[keyEvent.eventName]
end 

-- key will be nil if not from keyUp, or keyDown, such as if it's on tick
local function handleKeyEvents(key)
    if key == nil then
        key = _keysHeld[1]
    end

    -- If our input isn't a table with the type of key, and also has a type (user defined type, not programming type)
    if not( type(key) == "table" and key.type == "key") and (not key.type == nil) then
        if type(key) == "number" then
            key = createKeyDescriptor(key, false, false)
        elseif type(key) == "string" then
            -- Try not to define keys via strings, because they have less info in them
            local _key = createKeyDescriptor(nil, false, false)
            _key.keyName = key
            key = _key
            
        end
    -- Otherwise if it is a key, meaning it has the type of key, is a table. 
    else if (type(key) == "table" and key.type == "key") then
    --    key = {key}
    end

    -- Event Management Starts here

    -- Go through all the events and if they use this key then mark it as held or unheld
    for a,b in pairs(registeredKeyEvents) do
        
        for i,v in pairs(b) do

            local allHeld = true
                if v.keysHeld == nil then
                    for i2,v2 in ipairs(v.keysForEvent) do
                        v.keysheld[v2] = createKeyDescriptor(nil, v2, false, true) 
                    end
                end
                
                for i2,v2 in pairs(v.keysHeld) do
                    if i2 == key.keyName then
                        v.keysHeld[i2] = not key.isUp
                    end
                    allHeld = (allHeld and v.keysHeld[i2])
                end
                
                --debug.debug()
            -- If not all keys are held
            if (not allHeld) then
            -- then check if this is the first frame of this
                if v.requirementsMet then
                    -- If it is, then we check if we have a associated event
                    if not (v.releaseEventEffect == nil) then
                        v.releaseEventEffect(key)
                        if not v.keyboardStyle then
                            eventsHeld[v.id] = nil
                        end
                    end
                end
                -- Set requirements met to it's correct value at the end.
                v.requirementsMet = allHeld
            else 
                -- if this is the first frame that we have all keys held
                if (not v.requirementsMet) then
                    -- then fire the press event, if it exists
                    if not (v.pressEventEffect == nil) then
                        v.pressEventEffect(key)
                        if not v.keyboardStyle then
                            v.id = nextID
                            nextID = nextID + 1
                            eventsHeld[nextID] = v
                        end
                    end
                else 
                    -- this is not the first frame, and therefore this key is held
                    -- check if the event exists, then fire it
                    if (not (v.heldEventEffect == nil)) and v.keyboardStyle then
                        v.heldEventEffect(key)
                    end
                end
            end
            -- Set requirements met to it's correct value at the end.
            v.requirementsMet = allHeld
            end
        end
    end 
end

-- Runs whenever a key is pressed, and also whenever they repeat from holding
local function onKeyDown(_ev, key, isHeld)
    --print("Key DOWN!")
    --debugger.print("KEY DOWN: " .. key)
    local keyDescriptor = createKeyDescriptor(_ev, key, isHeld, false)
    
    _keysHeld[keyDescriptor.keyID] = keyDescriptor
    handleKeyEvents(keyDescriptor)
end


-- Runs whenever a key is released, probably???????????????
    -- The probably part of this fixed. It was as a result of statistics and an event consumption issue
local function onKeyUp(_ev, key)
    --print("Key UP!")
    --debugger.print("KEY UP: " .. key)

    local keyDescriptor = createKeyDescriptor(_ev, key, false, true)

    if _keysHeld[keyDescriptor.keyID] ~= nil then
        _keysHeld[keyDescriptor.keyID] = nil 
    end

    handleKeyEvents(keyDescriptor)
end
local function onChar(_ev, key)
    local keyDescriptor = createKeyDescriptor(_ev, key, false, false)

    handleKeyEvents(keyDescriptor)

    keyDescriptor.isUp = _keysHeld[keyDescriptor.keyID] == nil 
    handleKeyEvents(keyDescriptor)
end

-- A tell all denotation of a key. Pretty useful.
function createKeyDescriptor(_event, key, IsHeld, IsUp)
    local keyDescriptor = {
        type = "key",
        keyID = key,
        isHeld = IsHeld,
        isUp = IsUp,
    }
    
        keyDescriptor.keyName = type(key) == "number" and keys.getName(key) or "error"
        if type(key) =="string" then
            keyDescriptor.keyName = key
        end

    return keyDescriptor
end

--[[+--------------------+
----| LIFE CYCLE SECTION |
-------------------------+]]

    -- The init function will return a table of things that any attached apis will use to complete init
    local function init(modules, core)
        coreModule = core
        BedrockInput.RegisterAllPeripherals()
        if debugItems.debugMode then
            if true then -- TODO
            
            end
        end 
    end

    local managerBackup = _G.peripheralManager
    local function main()
        -- A basic way to pray to god they don't delete my bare minimums
        if _G.peripheralManager == nil or next(_G.peripheralManager) == nil then
            _G.peripheralManager = managerBackup
        end
        
        managerBackup = _G.peripheralManager

        for i,v in pairs(eventsHeld) do
            if v.requirementsMet then
                v.heldEventEffect()
            else 
                eventsHeld[i] = nil
            end
        end
    end

    local function cleanup()

    end
    
--[[+------------------+
----| API  DEFINITIONS |
-----------------------+]]

BedrockInput = {
    type = "BedrockModule",
    moduleDefinition = {
        Init = init,
        Main = main,
        Cleanup = cleanup,
        moduleName = "Input",
        events = {
            {
                eventName = "key",
                eventFunction = onKeyDown
            },
            {
                eventName = "key_up",
                eventFunction = onKeyUp
            },
            {
                eventName = "peripheral",
                eventFunction = onPeripheralConnect
            },
            {
                eventName = "peripheral_detach",
                eventFunction = onPeripheralDetach
            },
        },
        version = "0.0.0",
        priority = 1
    },
    keysHeld = _keysHeld,
    RegisterKeyEvent = registerKeyEvent,
    HandleKeyEvents = handleKeyEvents,
    RegisterAllPeripherals = registerAllPeripherals,
    GetPeripheralFromObject = getPeripheralFromObject,
    GetPeripheralByType = getPeripheralByType,
    IsPeripheralTypeConnected = isPeripheralTypeConnected,
    GetPeripheralFromText = getPeripheralFromText,
    GetGenericDisplayPeripheral = getGenericDisplayPeripheral,
    CreateKeyDescriptor = createKeyDescriptor,
}

return BedrockInput

