local BedrockDebug = {}
local runningDebuggers = {}

local DebuggerBuilder = {}
local Debugger = {}

function DebuggerBuilder:new()
    local builder = {
        logMaxSize = 15, -- The maximum that will be stored in RAM.
        logItems = {},
        built = false,
        active = false,
    }
    builder = setmetatable(builder, {__index = DebuggerBuilder})

    local returned = {}
    returned = setmetatable(returned, {__index = builder, __newindex = function (t, k, v) error("Object is read only!") end})
    return returned
end

local validOutputs = {
}

local outputSchema = {}
function outputSchema:addVarExpects(...)
    local vars = table.pack(...)
    for i,v in ipairs(vars) do
        table.insert(self.vars, v)
    end

    return self
end
function outputSchema:removeVarExpects(...)
    local vars = table.pack(...)
    for i,v in ipairs(vars) do
        table.remove(self.vars, v)
    end

    return self
end

function outputSchema:addWriteLogic(func)

end

local function createOutputSchema(name, ...)
    local schema = {
        types = {},
        vars = {}
    }
    for i,v in ipairs(table.pack(...)) do
        schema.types[v] = true
    end
    setmetatable(schema, {__index = outputSchema})

    validOutputs[name] = schema
    return schema
end
    -- Define various schemas and what types of objects they can be made with.
    createOutputSchema("file", "string") -- String for the path
    createOutputSchema("monitor", "table", "string")
    createOutputSchema("stream", "any") -- Stream just outputs the chars 1 by 1.

function DebuggerBuilder:addOutput(outputType, ...)

end

function DebuggerBuilder:build()
    -- Grab the not readonly copy
    local item = getmetatable(self).__index

    -- Imbue it with it's new functions then run it.
    setmetatable(item, {__index = Debugger})
    item:run()

    return self
end

local function init(modules, args)
    
end

local function main(deltaTime)
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
        dependencies = {
            requirements = {
                {moduleName = "Core", version = "*"},
            },
            optional = {
                {moduleName = "Graphics", version = "*"}, -- needed for widgets.
            },
            conflicts = {

            }
        },

        version = "0.0.0",
    },
    debuggerBuilder = DebuggerBuilder
}

return BedrockDebug