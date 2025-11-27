local deviceDescriptor = {}

local coreInstance = nil

local sideTimers = {}

local function toggle(side)
    local sidesToSet = {}

    if side ~= nil then
        table.insert(sidesToSet, side)
    else
        sidesToSet = redstone.getSides()
    end

    for i,v in pairs(sidesToSet) do
        local inp = redstone.getAnalogInput(v)

        if inp > 0 then
            redstone.setOutput(v, false)
        else
            redstone.setOutput(v, true)
        end
    end


end

local function turnOn(side, strength)
    local sidesToSet = {}

    if side ~= nil then
        table.insert(sidesToSet, side)
    else
        sidesToSet = redstone.getSides()
    end
    for i,v in pairs(sidesToSet) do
        redstone.setAnalogOutput(v, strength or 15)
    end
end

local function turnOff(side)
        local sidesToSet = {}

    if side ~= nil then
        table.insert(sidesToSet, side)
    else
        sidesToSet = redstone.getSides()
    end
    for i,v in pairs(sidesToSet) do
        redstone.setAnalogOutput(v, 0)
    end
end

local function pulse(side, time, strength)
    if type(tonumber(side)) == "number" then
    print(type(side), side)
        -- basically if the side doesn't exist shift the args right by one.
        strength = time
        time = side
        side = nil
    end

    time = tonumber(time)
    strength = tonumber(strength)

    local sidesToSet = {}

    if side ~= nil then
        table.insert(sidesToSet, side)
    else
        sidesToSet = redstone.getSides()
    end

    for i,v in pairs(sidesToSet) do
        print(i,v)
        redstone.setAnalogOutput(v, strength or 15)

        -- If this side already has a pulse
        if sideTimers[v] ~= nil then
            sideTimers[v]:Cancel() -- Cancel the previous timer so it doesn't lose pulse early
        end

        -- Despite what the IDE might tell you. No core instance cannot be nil. That's literally the runner program's job.
        _, sideTimers[v] = coreInstance:queueTimer(time, function ()
                redstone.setAnalogOutput(v, 0)
                sideTimers[v] = nil
        end)
    end
end

local function init(modules)
    coreInstance = modules.coreInstance
    -- Add side detection later
    coreInstance:registerEvent("redstone", function (_ev)
        deviceDescriptor.events.onRedstoneEvent()
    end)
end

local function main()

end

local function cleanup()

end

deviceDescriptor = {
    deviceType = "RedstoneInterface", -- Used mostly for grouping
    deviceName = "Basic RI MK.1", -- Basic Redstone Interface Device Mark One. You think it's plug and play?
    functions = {
        -- functions need to be lowercase because the thing that interprets commands takes a string.lower of it's input
        toggle = toggle,
        turnoff = turnOff,
        turnon = turnOn,
        pulse = pulse,
    },
    variables = {
    },
    -- Events get populated by our runner. As such we don't put anything here.
    events = {
        onRedstoneEvent = function () end,
    },
    init = init,
    main = main,
    cleanup = cleanup,
    -- Quit is also populated by our runner
    quit = function ()
    end
}

return deviceDescriptor