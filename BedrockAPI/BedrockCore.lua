--[[+----------------------------------------------------------+
    |                      CORE MODULE                         |
    |                    +------------+                        |
    | What this module handles: Events, Module registration,   |
    | real time timer events, Connecting with real projects,   |
    |                 and Module life cycle                    |
    |                      Description:                        |
    |  This module is designed to handle all other modules in  |
    |  the BedrockAPI, and give them a good way to be used by  | 
    |                     our end users                        |
    +----------------------------------------------------------+
---------------------------------------------------------------]]

--NOTE: Only the first requirer of Bedrock will get the real reference.

local BedrockCore = {}

local firstLoad = _G.BedrockCore == nil

if not firstLoad then
    table.insert(_G.BedrockCore.users, debug.getinfo(3, "f").func)
    if _G.BedrockCore.enforceSingleness then
        _G.BedrockCore = {}
        _G.BedrockCore.enforceSingleness = true
    else
        return _G.BedrockCore.CoreReference()
    end
end
--_G.BedrockCore = BedrockCore

local selfReference = debug.getinfo(1, "S")

-- Basically we only accept calls from our trustedCaller
local trustedCaller = debug.getinfo(3, "S")
    -- Preventing a potential edge case where require in real CC envs are not just a function
    trustedCaller = trustedCaller or debug.getinfo(2, "S")
local regenerateCoreReference = function ()
    -- This is overwritten near the end. This declaration is so lua doesn't complain we don't have a function with this name
    error("Illegal State! Function called before program run?")
end
local registeredCores = {}

CoreBuilder = {}

local deprecatedFunctions = {}

local terminate = false

local shared = {
    maxId = 0
}

local nameIDpair = {}
    local function addSharedValue(Value, Name)

        if nameIDpair[Name] ~= nil and (Name ~= "" or Name ~= nil) then
            return false, "Name already exists! Consider modifying?"
        end
        -- The value with some metadata
        local addedValue = {
            name = Name,
            id = nil,
            value = Value,
            size = #Value or 1,

            --Core will ignore these two when internally removing it (it'll call it, but ignore it's return)
            -- This is our equivalent of {get; set;}

            -- Use to add conditions to removing your value
            onRemove = function ()
                return true
            end,

            -- Use to add conditions to modifying your value; 
            onModify = function (self, newValue)
                return true, newValue
            end,

            -- Use to declare how you want to be read. Don't want to be read? Error or return nil.
            onRead = function (self)
                return true, self.value
            end

        }

        local addShared

        for i,v in ipairs(registeredCores) do
            -- Basically if anyone returns anything we say that's an acceptance and continue to our own checks
            addShared = v.hooks.PreAddSharedValue(Value, addedValue) or addShared
            if addShared ~= nil then 
                break
            end
        end

        if addShared then
            shared.maxId = shared.maxId + 1
            addedValue.id = shared.maxId
            -- TODO add checks of our own before adding the value
            shared[addedValue.id] = addedValue
            nameIDpair[addedValue.name] = addedValue.id

            -- So you can modify your getters and setters.
            return addedValue
        end

        -- We failed.
        return false, "Value addition declined"
    end

    local function removeSharedValue(id)
        -- Convert the name into an ID
        if type(id) == "string" then
            id = nameIDpair[id] 
            if id == nil then
                return false, "Invalid ID reference"
            end
        elseif type(id) == "table" then
            id = id.id
        end

        if shared[id] ~= nil and shared[id].onRemove ~= nil and shared[id].onRemove() then
            shared[id] = nil
            return true
        end
        return false, "No value found!"
    end

    -- Get object by ID
    local function getSharedValue(id)
        -- Convert the name into an ID
        if type(id) == "string" then
            id = nameIDpair[id]
            if id == nil then
                return false, "Invalid ID reference"
            end
        elseif type(id) == "table" then
            id = id.id
        end

        if shared[id] ~= nil and shared[id].onRead ~= nil  then
            local values = table.pack(shared[id]:onRead())
            local allowRead = table.remove(values, 1)
            if not allowRead then
                return false, "You are not allowed to read this value!" 
            else
                return table.unpack(values)
            end
        end
        return false, "No value found!"
    end
    local function modifySharedValue(id, newValue)
        if type(id) == "string" then
            id = nameIDpair[id] 
            if id == nil then
                return false, "Invalid ID reference"
            end
        end

        local continue, computedValue = shared[id]:onModify(newValue)
        if shared[id] ~= nil and shared[id].onModify ~= nil and continue then
            shared[id] = computedValue
            return true, "Success"
        end
        return false, "No value found!"
    end

    --- Assumedly checks deprecations. Doesn't work...
    local function checkDeprecated()
        -- It's gotta be one of them! Right?
        local f = debug.getinfo(4) or debug.getinfo(3) or debug.getinfo(2)
        
        -- Well... Crap.
        if f == nil then
            return
        end

        for i,v in ipairs(deprecatedFunctions) do

            -- This doesn't work. Complete later. I think this is the most stable heuristic I can think of. Lua got no function ids? I'm going to cry. At this point I might try to stringing it and seeing what happens...
            if (v.funcDetails.source == f.source) and (v.funcDetails.nparams == f.nparams) then
                for i,v in ipairs(registeredCores) do
                    v.hooks.onDeprecatedCall(v.func, v.extraInfo, v.severity or 0)
                end
            end 
        end
    end
    debug.sethook(checkDeprecated, "c")

    function CoreBuilder:deprecateFunction(Func, ExtraInfo, Severity)
        local deprecationBody = {
            funcDetails = {},
            extraInfo = ExtraInfo,
            severity = Severity
        }
        deprecationBody.funcDetails = debug.getinfo(Func)
        
        table.insert(deprecatedFunctions, deprecationBody)
        return self
    end

    -- Hooks as a pattern here are formatted the same, and are usually just used different.   
    -- I don't know how document what the ... means. whatever  

    --- Creates and adds the generic hook pattern to an object.
    --- @param obj table
    --- @param hookName string
    --- @param ... any -- The type that params the hook uses expects. Doesn't need a real variable, and won't use it, anyway.
    function CoreBuilder:createHook(obj, hookName, ...)

        local hookBase = {
            funcs = {},
            maxFuncID = 0,
        }

        --- Add a function into the hook base. It's hooking into a hook
        --- @param func function
        --- @return hookFunc # A function with some metadata attached
        hookBase.addHook = function (func)
            hookBase.maxFuncID = hookBase.maxFuncID + 1
            local funcBase = {
                id = hookBase.maxFuncID,
                event = func
            }
            
            hookBase.funcs[hookBase.maxFuncID] = funcBase
            return funcBase
        end

        --- Removes a hooked in function by it's ID
        --- @param id integer # The ID returned with the function you added.
        hookBase.removeHook = function (id)
            hookBase.funcs[id] = nil
        end

        -- We need this table to be a metatable to use it's call
        setmetatable(hookBase, hookBase)

        -- When the table is called, run all the hooked in functions in parallel
        hookBase.__call = function (self, ...)

            local args = {...}
            local toBeCalled = {}
            self.returned = {}

            -- Assert that there aren't any type errors.
            for i,v in pairs(args) do
                -- The ~ symbol after mismatch was a typo, but I'm not removing it.
                if (not (type(v) == self.args[i] or self.args[i] == "any" or self.args[i] == nil)) then
                    error("Type mismatch~ (Expected: " .. tostring(self.args[i]) .. " Got: " .. type(v) .. ")", 2)
                end 
            end

            -- Add all the functions together in a way we can call without args
            for i, v in pairs(self.funcs) do
                table.insert(toBeCalled, function ()
                    self.returned[i] = v.event(table.unpack(args))
                end)
            end
            local parallels = table.pack(parallel.waitForAll(table.unpack(toBeCalled)))
            local localReturneds = self.returned
            self.returned = {}
            -- Run them in parallel.
            return next(localReturneds) ~= nil and localReturneds or nil, parallels
            
        end

        hookBase.args = {}

        -- Is this legal? who knows
            -- I see the confusion. No. Nothings legal in code.
        for _,v in pairs({...}) do
            if type(v) ~= "string" then
                table.insert(hookBase.args, type(v))
            else
                table.insert(hookBase.args, string.lower(v))
            end
        end

        if obj.hooks == nil then
            obj.hooks = {}
        end
        -- create the hook on the actual object we were given.
        obj.hooks[hookName] = hookBase

        return self
    end
    -- If you want to delete a hook just set it to nil. We have no tracking we need to do with it.

--- Cleans up all attached core in preperation for shutdown. Can only be called by a trusted caller
local function APICleanup(disallowShutdown, sourceOverride)


    local caller = debug.getinfo(2, "S")
    if disallowShutdown then
        caller = sourceOverride or caller
    end
    -- Hey its me. A private method. God I wish.
        -- Someone tell lua we already had a good solution for this.
    if (trustedCaller ~= nil and trustedCaller.source == caller.source) or selfReference.source == caller.source then
        for i,v in pairs(registeredCores) do
            for i2,v2 in pairs(v.modules) do
                -- Avoiding a quick stack overflow
                if v2.moduleDefinition.moduleName ~= "Core" then
                    pcall(v2.moduleDefinition.Cleanup)
                end
            end
        end
        if not disallowShutdown or disallowShutdown == nil then
            firstLoad = true
            trustedCaller = nil
            _G.BedrockCore = nil
            registeredCores = {}
            debug.sethook(nil, "c")
        else
            trustedCaller = caller
        end
    elseif trustedCaller ~= nil then
        return nil, "You aren't the owner of this module!"
    else 
        trustedCaller = trustedCaller or "nil"
        print(trustedCaller or "nil",trustedCaller ~= "nil" and trustedCaller.source or "nil")
        print(debug.getinfo(2, "S").source)
        -- Just in case
        _G.BedrockCore = nil
        firstLoad = true
        trustedCaller = nil
        -- Erroring here is fine because it's before we've ever started.
        error("Illegal state! Core hasnt been started yet?")
    end
end


local function checkVersion(versionGot, versionExpected, operand)
    -- Wildcard case
    if versionExpected == "*" then
        return true
    end

    if operand == nil then
        operand = ">=" -- Backwards compatibility.
    end

    assert(type(operand) == "string", string.format("Operand is not a string? Type: %s", type(operand)))
    assert(type(versionGot) == "string" and type(versionExpected) == "string", string.format("Version is not a string? Type: %s, %s", type(versionGot), type(versionExpected)))
    -- All right I'm just gonna admit it now; I'm gonna cheat. This will have edge cases, but the intended cases'll work fine.

    if #operand > 2 then
        error(string.format("Operand is too long! (Operand is %s)", operand))
    end

    local gotValues = table.pack(string.match(versionGot, "^(%d+)%.(%d+)%.(%d+)"))
    local expValues = table.pack(string.match(versionExpected, "^(%d+)%.(%d+)%.(%d+)"))

    assert(#gotValues == 3 and #expValues == 3, "Version malformed?")

    -- I can cheat like this since logically I should always get three values from those matches.
    for i,v in ipairs(gotValues) do
        gotValues[i] = tonumber(v)
        expValues[i] = tonumber(expValues[i])
    end

    local gotGreater = false -- If it's equal then it's not greater so we only need to check after that condition is met 
    local isEqual = true


    -- This reminds me of a fun recursive hell I once knew.

    for i,v in ipairs(gotValues) do
        isEqual = gotValues[i] == expValues[i]
        -- If the major isn't equal we also don't need to cascade
        if not isEqual then
            gotGreater = gotValues[i] > expValues[i]
            break
        end
    end

    -- Oh god

    if isEqual then
        local gotPrerelease = string.find(versionGot, "-", 1, true)
        local expPrerelease = string.find(versionExpected, "-", 1, true)
        isEqual = (gotPrerelease == nil) == (expPrerelease == nil)

        -- 500 cascades.
        -- If neither have a pr then theres nothing else we can do, they're equal.
        if isEqual and (gotPrerelease ~= nil) then
            versionGot = string.sub(versionGot, gotPrerelease + 1, string.find(versionGot, "+", gotPrerelease, true) or #versionGot)
            versionExpected = string.sub(versionExpected, expPrerelease + 1, string.find(versionExpected, "+", expPrerelease, true) or #versionExpected)

            gotValues = {}
            expValues = {}

            -- Could someone tell me why match and gmatch function different past one being an iterator. That's really stupid.
            for v in string.gmatch(versionGot, "[0-9A-Za-z-]+") do
                table.insert(gotValues, v)
            end

            for v in string.gmatch(versionExpected, "[0-9A-Za-z-]+") do
                table.insert(expValues, v)
            end

            local iterated = #gotValues <= #expValues and gotValues or expValues 
            for i,v in ipairs(iterated) do
                isEqual = gotValues[i] == expValues[i]
                -- If it isn't equal we also don't need to cascade
                if not isEqual then
                    -- theoretically this should turn it into a number if it can be one
                    gotValues[i] = tonumber(gotValues[i]) or gotValues[i]
                    expValues[i] = tonumber(expValues[i]) or expValues[i]
                    if type(gotValues[i]) == type(expValues[i]) then
                        gotGreater = gotValues[i] > expValues[i]
                        break
                    else
                        -- assume that gotValues is the non numeric one. Ignoring a handful of illegal states.
                        gotGreater = type(gotValues[i]) == "string"
                        break
                    end
                end
            end
            
            if isEqual and #gotValues ~= #expValues then
                isEqual = false
                gotGreater = #gotValues > #expValues
            end
        elseif not isEqual then
            gotGreater = not gotPrerelease
        end
    end



    local opFirstPart = string.sub(operand, 1,1)
    local opSecondPart = #operand > 1 and string.sub(operand, 2,2) or ""

    if opSecondPart == "=" then

        -- We can't unconditionally return, because if it's not equal it could be less than or greater than
        if isEqual then
            return true 
        end
    end

    if opFirstPart == ">" then
        return gotGreater
    elseif opFirstPart == "<" then
        return not gotGreater
    elseif opFirstPart == "=" then
        return isEqual
    end

    return false, "Error in version checking?"
end

--- Resolves all dependencies for a core.  
--- This means checking versions, and collating requirements, optional modules, and checking for conflicts.
--- @param core table  # The core we check the modules of
---@param module table # The module in question
local function resolveDependencies(core, module)
        local returnedModules = {}
        local coreModules = {}
        
        for _,v in ipairs(core.modules) do
            coreModules[v.moduleDefinition.moduleName] = v
        end

        -- If you don't have dependencies then this'll be nil. If the BIOS can check proxies like this, so can I.
        if module.moduleDefinition.dependencies then
            -- If so, then check which types.
            

            for _,v2 in ipairs(module.moduleDefinition.dependencies.requirements) do 
                
                assert(coreModules[v2.moduleName] ~= nil, "Module " .. module.moduleDefinition.moduleName .. " is missing dependency " .. v2.moduleName .. "!")
                if not checkVersion(coreModules[v2.moduleName].moduleDefinition.version, v2.version, v2.operand) then
                    error("Version of module:" .. module.moduleDefinition.moduleName .. " is incorrect! (Expected version " .. v2.minimumVersion .. " or higher, Got version " .. coreModules[v2.moduleName].moduleDefinition.version)
                end
                returnedModules[v2.moduleName] = coreModules[v2.moduleName]
            end

            for _,v2 in ipairs(module.moduleDefinition.dependencies.optional) do
                if coreModules[v2.moduleName] ~= nil and checkVersion(coreModules[v2.moduleName].moduleDefinition.version, v2.version, v2.operand) then
                    returnedModules[v2.moduleName] = coreModules[v2.moduleName]
                end
            end

            for _,v2 in ipairs(module.moduleDefinition.dependencies.conflicts) do
                -- If you pcall it and force it to go through then we'll force conflicts to go through
                if coreModules[v2.moduleName] ~= nil and checkVersion(coreModules[v2.moduleName].moduleDefinition.version, v2.version, v2.operand) then
                    coreModules[v2.moduleName] = nil
                    error("Module " .. module.moduleDefinition.moduleName .. " has conflicting dependency, " .. v2.moduleName .. "!")
                end
                returnedModules[v2.moduleName] = coreModules[v2.moduleName]
            end
            
            
        end
    return returnedModules
end

--- Dispatches events to interested observers; DO NOT CALL ON YOUR OWN. THERE IS ONLY ONE PLACE THIS SHOULD BE USED
--- Also this is infinitely blocking. Excluding errors, or termination.
local function eventHandler(focus)
    while true do
        local event = table.pack(os.pullEvent())
        local eventName = event[1]
            for _,v in pairs(registeredCores) do
            if (multishell ~= nil and focus == multishell.getCurrent()) or true then 
                if v.focus == focus then
                    local flaggedEventFuncs = {}
                    if v.events ~= nil then
                        flaggedEventFuncs = {}
                        for i2, v2 in pairs(v.events) do
                            if v2.eventName == eventName then
                                table.insert(flaggedEventFuncs, function ()
                                    local success, message = pcall(v2.eventFunction, table.unpack(event))
                                    if not success then
                                        v.hooks.onEventError(event, message, v2)
                                        local results = v.hooks.onEventError.results
                                        if not results then
                                            error(message, 3)
                                        end
                                    end
                                end)
                            end
                        end
                        local success, message = pcall(function() parallel.waitForAll(table.unpack(flaggedEventFuncs)) end) 
                        if not success then
                            error(message, 3)
                        end
                    end
                end
            end
        end
    end
end

--- Registers an event for a given core.
function CoreBuilder:registerEvent(EventName, EventFunction)
    assert(type(EventFunction) == "function", string.format("The attached callback (%s) is not a function!", tostring(EventFunction)))
    self.numEvents = self.numEvents ~= nil and self.numEvents + 1 or 1
    if self.events == nil then
        self.events = {}
    end
    local event = {
        eventName = EventName,
        eventFunction = EventFunction

    }
    event.id = self.numEvents
    self.events[self.numEvents] = event
    return self, event
end

function CoreBuilder:relinquishEvent(event)
    -- Creates holes instead of removing them for quicker individual event removal, and less required tracking
    local eventID = event.id or event
    if type(eventID) ~= "number" then

        if not self.hook.Log("Given event wasn't a number or table", "warning") then
            error("Given event wasn't a number or table!")
        end
    end

    
    local removalSuccess = self.events[event.id] ~= nil
    self.events[event.id] = nil
    return self, removalSuccess
end

--- Queues a callback at a later REAL TIME point. 
function CoreBuilder:queueTimer(ms, callbackFunc)
    assert(type(ms) == "number", string.format("Time given (%d) is not a number!", ms))
    assert(type(callbackFunc) == "function", string.format("Callback given (%s) is not a function!", tostring(callbackFunc)))

    local timer = {
        maxDuration = ms,
        duration = ms,
        callback = callbackFunc,
        justAdded = true
    }
    
    self.hooks.onTimerAdded(timer)
    table.insert(self.timers, timer)
    timer.Cancel = function ()
        self.hooks.onTimerRemoved(timer)
        -- Finds our timer and deletes it completely. Just entirely
        for i2,v2 in ipairs(self.timers) do
            if v2 == timer then
                -- The removal of organic substances has now begun
                table.remove(self.timers, i2)
                timer = nil
                break
            end
        end
    end
    return self, timer
end

function CoreBuilder:new()
    local caller = debug.getinfo(2, "f").func
    local builder = {
        timers = {},
        func = caller,
        focus = multishell ~= nil and multishell.getCurrent() or 1,
        isBuilt = false
    }


    setmetatable(builder, self)
    
    
    
    self.__index = self
    
    -- 500 ̶c̶i̶g̶a̶r̶e̶t̶t̶e̶s hooks

    --- Module Modification Hooks
    --- @param attachedCoreModules table # The modules in the core
    --- @param module table # The module modified

    self:createHook(self, "onModuleAdd", "table", "table"):createHook(self, "onModuleRemove", "table", "table")

    --- On Build hook
    --- @param modules table # The attached modules at time of build
    self:createHook(self, "onBuild", "table")

    --- @param deltaTime number # deltatime
    --- @param core table # the core that updated
    self:createHook(self, "onUpdate", "number", "table")

    --- Timer Hooks
    --- @param timerObj table # an object representing the added timer
    self:createHook(self, "onTimerAdded", "table")
    self:createHook(self, "onTimerRemoved", "table")
    self:createHook(self, "onTimerElapsed", "table")

    
    
    --- @param attachedModules table # The attached modules at time of the error
    --- @param module table # The module at fault
    --- @param message string
    --- @param errorFunc table
    --- @return table | boolean # whether to throw or not
    self:createHook(self, "onModuleError", "table", "table", "string", "any")

    --- @param event table # The CC event.
    --- @param message string # The error message
    --- @param erroredEvent table # The event object we make
    self:createHook(self, "onEventError", "table", "string", "table")

    self:createHook(self, "onDeprecatedCall", "function", "any", "number")

    -- Pattern is message, severity, level, extras
    self:createHook(self, "Log", "string", "string", "number")


    -- Used to precheck the shared value before we add it
    -- it's params are the object and it's metadata
    self:createHook(self, "PreAddSharedValue", "any", "table")
    
    -- We add ourself for other modules to use our features. Do account for this. Please.
    self:addModule(BedrockCore)
    -- This is just for logging. It won't save the program if it's in peril, here. Other places though
    self.hooks.onModuleError.addHook(function(allModules, moduleAtFault, errMsg, func) return builder.hooks.Log(errMsg, "error", 2, allModules, moduleAtFault) end)
    self.hooks.onEventError.addHook(function(event, errMsg, evObj) builder.hooks.Log(errMsg, "error", 2, evObj, event) end)

    return builder
end

function CoreBuilder:addModule(module)
        if self.modules == nil then
            self.modules = {}
        end
        table.insert(self.modules, module)

    if self.isBuilt then
        
        local givenModules = resolveDependencies(self, module)

        module.moduleDefinition.Init(givenModules, self.__index)
        for i2,v2 in pairs(module.moduleDefinition.events) do
            self:registerEvent(v2.eventName, v2.eventFunction)
        end

        -- make sure no module conflicts with this one.
        for i,v in ipairs(self.modules) do
            -- If this exists, then feed in the modules
            if v.moduleDefinition.OnModuleChange and v ~= module then
                v.moduleDefinition.OnModuleChange(resolveDependencies(self, v))
            end
        end
        

        -- I'm playing with fire here.
        --error("You can't modify modules in a built core!")
    end
    

    
    self.hooks.onModuleAdd(self.modules, module)
    return self
end

-- I have no clue why you'd need this one, but people are more creative than I am
    -- Well after the update to allow post build removal it's logical for resource management

---Removes a module from the core
function CoreBuilder:removeModule(module)
-- Just gonna do it slow because we won't have too many modules
    -- Check if this core has already been built. 
        -- Find and remove the given module. 
        local found = false
        for i,v in ipairs(self.modules) do
            if module.moduleDefinition.moduleName == v.moduleDefinition.moduleName then
                table.remove(self.modules, i)
                found = true
                break
            end
        end
        if not found then
            self.hooks.Log("Module not found!", "warning", 2)
            return self, false, "Module not found!"
        end
    if self.isBuilt then


        -- make sure no module needed that one.
        for i,v in ipairs(self.modules) do
            -- If this exists, then feed in the modules
            if v.moduleDefinition.OnModuleChange then
                v.moduleDefinition.OnModuleChange(resolveDependencies(self, v))
            end
        end
        module.moduleDefinition.Cleanup()
        -- This is probably a can of worms I shouldn't be opening
        --error("You can't modify modules in a built core!")
    end

    self.hooks.onModuleRemove(self.modules, module)

    return self
end

function CoreBuilder:build()
    if not self.isBuilt then
        self.hooks.onBuild(self.modules)
        self.DeltaTime = 0
        self.timeOfLastFrame = os.epoch("utc")

        if registeredCores[self.focus] ~= nil then
            registeredCores[self.focus].hooks.Log("Forced shutdown from invalid state!", "fatal", 1, self)
            self.hooks.Log("Previous core improperly shut down!", "warning", 1)
            registeredCores[self.focus]:Cleanup(true, debug.getinfo(2, "S")) -- Even the ones who should not exist deserve cleanup
            registeredCores[self.focus] = nil 
        end
        registeredCores[self.focus] = self
        for _,v in ipairs(self.modules) do
            
            
            local givenModules = resolveDependencies(self, v)
            -- check if this module has deps

            -- Hand over only our functions and the needed modules
            v.moduleDefinition.Init(givenModules, self.__index)
            for i2,v2 in pairs(v.moduleDefinition.events) do
                self:registerEvent(v2.eventName, v2.eventFunction)
            end
            -- start a timer if a time slice is declared
            if v.moduleDefinition.runRate and v.moduleDefinition.runRate > 0 then
                local runFunc = function () end
                runFunc = function ()
                    v.moduleDefinition.Main()
                    self:queueTimer(v.moduleDefinition.runRate, runFunc)
                end
                self:queueTimer(v.moduleDefinition.runRate, runFunc)
            end
        end
        self.hooks.onBuild(self.modules)
        self.isBuilt = true
    end
    return self
end


function CoreBuilder:Cleanup(disallowShutdown)
    parallel.waitForAny(function() os.sleep(2) end, function ()
        if self ~= nil then
            self.events = nil
            for i,v in pairs(self.modules) do
                if i ~= "Core" then
                    pcall(v.moduleDefinition.Cleanup)
                end
            end
            for i,v in pairs(registeredCores) do
                if v == self then
                    table.remove(registeredCores, i)
                    break
                end
            end
            if #registeredCores == 0 then
                APICleanup(disallowShutdown)
            end
        end
    end)
end

local function update(focus)
    while not terminate do
        local coreRunners = {}
        for i,v in pairs(registeredCores) do
            if (multishell ~= nil and focus == multishell.getCurrent()) or true then 
            if v.focus == focus then
                table.insert(coreRunners, function ()
                v.DeltaTime = os.epoch("utc") - v.timeOfLastFrame
                v.timeOfLastFrame = os.epoch("utc")
                v.hooks.onUpdate(v.DeltaTime, v)
                
                local completedTimers = {}
                local newTimers = {}
                for i2,v2 in pairs(v.timers) do
                    v2.duration = v2.duration - v.DeltaTime
                    if v2.justAdded then
                        table.insert(newTimers, i2)
                    end

                    if v2.duration <= 0 and not v2.justAdded then
                        v.hooks.onTimerRemoved(v2)
                        v.hooks.onTimerElapsed(v2)
                        v2.callback(v2.maxDuration - v2.duration) -- Incorporate the exact time it took to elapse. The subtraction of duration is there to represent how much over the time we are.
                        table.insert(completedTimers, i2)
                    end
                end

                for i2,v2 in ipairs(completedTimers) do
                    v.timers[v2] = nil
                end
                -- Prevents timer callbacks that add timers from having the ability to lock up thread.
                for i2,v2 in ipairs(newTimers) do
                    v.timers[v2].justAdded = false
                end

                local coremains = {}
                for i2,v2 in pairs(v.modules) do
                    -- An approximation for time slicing
                    if not v2.moduleDefinition.runRate or v2.moduleDefinition.runRate <= 0 then
                        for i=1, v2.moduleDefinition.priority or 0 do
                        table.insert(coremains, function ()
                            local success, message = pcall(v2.moduleDefinition.Main, v.DeltaTime)
                            if not success then
                                local results = v.hooks.onModuleError(v.modules, v2, message, debug.getinfo(2, "fSl"))
                                if not results then
                                    error(message, 3)
                                end
                            end
                        end)
                    end
                    end
                end
                --How much parallelism is too much parallelism?
                parallel.waitForAll(table.unpack(coremains))
                end)
            end
            end
        end

        -- Let them run in parallel. HAH WHY DO WORK WHEN THEY CAN DO IT FOR ME
        parallel.waitForAll(table.unpack(coreRunners))
        os.sleep(0)
    end
end

local function main()
end

local function init()
end

local function cleanup()

end

local function tick()
    -- Consider centralizing or semi centralizing event handling....

        -- We give out references to the original after the first load
        firstLoad = false
        -- Normally this is infinitely blocking, so if we get past this line we've errored.
        local _, message = pcall(parallel.waitForAny, function () eventHandler(multishell ~= nil and multishell.getFocus() or 1) end, function ()
            update(multishell ~= nil and multishell.getFocus() or 1)
        end)
        APICleanup()
        error(message, 0) -- This does offer more stability. Though I'm worried that rethrown errors will lose context...
        -- Use the error hook I guess...?
end

-- A core reference is just a copy of the core so overrides don't hamper function for others.
local function coreReference()
    local table = {}
    for i,v in pairs(BedrockCore) do
        table[i] = v 
    end
    return table
end

local function regenerateCoreReference()
    if firstLoad then
    BedrockCore = {
        type = "BedrockModule",
        users = {},
        moduleDefinition = {
            priority = 0, -- main is never called 
            -- How many ms between main calls. Disables the conventional mechanism TODO
            runRate = 0,
            Init = init,
            Main = main,
            Cleanup = cleanup,
            moduleName = "Core",
            events = {
            },
            dependencies = {
                requirements = {

                },
                optional = {

                },
                conflicts = {

                }
            },

            -- only core gets shared. (If you follow best practice) only it's allowed to inherently hold random info

            version = "0.0.0" -- I don't know how to version. So I'll figure this out on release. Nobody else is here to judge anyway.
        },
        coreBuilder = CoreBuilder,
        Tick = tick,
        Cleanup = APICleanup,

        -- HECK YOUR GLOBAL TABLE I WANT SECURITY
        AddSharedValue = addSharedValue,
        RemoveSharedValue = removeSharedValue,
        GetSharedValue = getSharedValue,
        ModifySharedValue = modifySharedValue,
        enforceSingleness = false,
        CoreReference = coreReference


    }
    end

    if not BedrockCore.enforceSingleness then
        _G.BedrockCore = coreReference()
        _G.BedrockCore.hooks = nil -- CORE hooks aren't given out to just anyone. -- Why'd I capitalize Core like that; This isn't undertale.
    else 
        _G.BedrockCore = {}
    end
end


regenerateCoreReference()
return BedrockCore

-- It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.
-- It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.
-- It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.
-- It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.It hurts.
-- Thanks for coming to my TED talk.

-- I hope you enjoyed your stay here at our hotel.  We'd love to see you again for another stay.