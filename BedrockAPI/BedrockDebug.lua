local BedrockDebug = {}

local runningDebuggers = {}

DebuggerBuilder = {}
    
function DebuggerBuilder:new()
    debugger.instance = {
        logItems = {}
    }
    setmetatable(debugger, self)
    self.__index = self  
    return debugger
end

function debugger:run()
    table.insert(runningDebuggers, self)
    self:drawExternals()
    return self
end

function debugger:stop()
    for i,v in ipairs(runningDebuggers) do
        if v == self then
            table.remove(runningDebuggers, i)
            break
        end
    end
    
    self:drawExternals()
    self:drawMain()
    
    return self
end

function debugger:setLogHeight(H)
    self.instance.textLogHeight = ((type(H) == "number") and H) or 15  
    return self
end

-- TODO: Make robust enough to handle devices from Input module, base CC. 
--       Also make work with monitors, the debugger tool, and also saving to a path
function debugger:addOutput(device)
    if self.instance.outputs == nil then
        self.instance.outputs = {}
    end
    local theType = type(device)
    if theType == "table" then
        table.insert(self.instance.outputs, device)
    elseif theType == "string" then
        if fs.isDir(device) then
            device = device .. "Log"
        end

        local number = 0
        
        if fs.exists(device) then
            while fs.exists(device .. " " .. number) do
                number = number + 1
            end
            device = device .. " " .. number
        end
        if string.find(device, ".") == nil then
            device = device .. ".txt"
        end
        table.insert(self.instance.outputs, device)
    end

    return self
end

function createLogMessage(message, info, severity, lifespan)
    local logMessage = {
        message = (type(message) == "string" and message) or "",
        lineCalled = info.currentline,
        caller = info.source,
        lifespan = lifespan,
        expandedInfo = {
            
        }
    }
    local fh = io.open(info.short_src, "r")
    for i = 1, info.currentline - 1 do
---@diagnostic disable-next-line: need-check-nil
        local _ = fh:read()
    end
---@diagnostic disable-next-line: need-check-nil
    local callingLine = fh:read()
    
    local outfo = debug.getinfo(2, "n")
    
    logMessage.expandedInfo.callingChar = string.find(callingLine, outfo.name)

    logMessage.expandedInfo.callingLineFull = callingLine
    callingLine = string.gsub(callingLine, "%s%s", "")
    callingLine = string.gsub(callingLine, "%c", "")
    logMessage.expandedInfo.callingLine = callingLine
---@diagnostic disable-next-line: need-check-nil
    fh:close()
    
    return logMessage
end

-- Helper functions to make logging a little simpler
function debugger:log(message, lifespan)
    local info = debug.getinfo(2, "Sln")
    local logMessage = createLogMessage(message, info, "info", lifespan)
    table.insert(self.instance.logItems, logMessage)

    return self
end

function debugger:logWarning(message, lifespan)
    local info = debug.getinfo(2, "Sln")
    local logMessage = createLogMessage(message, info, "warning", lifespan)
    table.insert(self.instance.logItems, logMessage)

    return self
end

function debugger:logError(message, lifespan)
    local info = debug.getinfo(2, "Sln")
    local logMessage = createLogMessage(message, info, "error", lifespan)
    table.insert(self.instance.logItems, logMessage)

    return self
end


-- Draw function for registered debug windows
-- Refresh at your own leisure.
function debugger:drawExternals()
    for i,v in (self.instance.outputs) do
        
        if self.enabled then
            local displayObject = v.monitor or (v.base.name == "debugger" and v) or (type(v) == "string" and v) or self:logError("Unexpected item in the rendering area.")
            term.write(displayObject)
            --for i2 = 1, v.
        end
    end
    return self
end

-- Draws my unity widgets.
-- GOD I LOVE WIDGETS YEAH YEAH YEAH WOOOO
-- Refresh whenever the screen draws.
function debugger:drawMain()

    return self
end

local function init(modules, args) 
    
end

local function main(deltaTime)
    -- Handle the frame events of debuggers.
    local removalQueued = {}
    local needsRepaint = false
    if runningDebuggers ~= nil and #runningDebuggers > 0 then
        for i,v in ipairs(runningDebuggers) do
            if v.lifespan ~= nil then
                v.lifespan = v.lifespan - deltaTime
                if v.lifespan <= 0 then
                    table.insert(removalQueued, i)
                    needsRepaint = true
                end
            end
        end
        
        for i,v in ipairs(removalQueued) do
            table.remove(runningDebuggers, v - (i - 1))
        end
        if needsRepaint then
            for i,v in ipairs(runningDebuggers) do
                v:drawExternals()
            end
        end
    end
end

local function cleanup()

end


BedrockDebug = {
    type = "BedrockModule",
    moduleDefinition = {
        Init = init,
        Main = main,
        Cleanup = cleanup,
        moduleName = "Debug",
        events = {
        },
    },
    debuggerBuilder = DebuggerBuilder
}

return BedrockDebug