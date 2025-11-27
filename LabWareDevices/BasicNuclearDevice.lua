-- This is a reflavored RedstoneInterface (RI) Device flavored in order to stop the fucking nuclear reactor from exploding

local deviceDescriptor = {}

local coreInstance = nil

local sideTimers = {}

local masterOff = false
local function toggle(side)
    side = "right"
    local sidesToSet = {}

    if side ~= nil then
        table.insert(sidesToSet, side)
    else
        sidesToSet = redstone.getSides()
    end

    for i,v in pairs(sidesToSet) do
        local inp = redstone.getAnalogInput(v)

        if inp > 0 then
            masterOff = true
            redstone.setOutput(v, false)
        else
            masterOff = false
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

local periph
local cable
local function init(modules)
    coreInstance = modules.coreInstance
    -- Add side detection later
    coreInstance:registerEvent("redstone", function (_ev)
        deviceDescriptor.events.onRedstoneEvent()
    end)

    periph = peripheral.find("energy_detector")

    cable = peripheral.wrap("front")

    if periph == nil or cable == nil then
        deviceDescriptor.quit(000)
        print(periph)
        error("Missing required probe!") -- We probe the cable for 'voltage' and shut down until it's come down if it's too high
    end
    masterOff = false
    periph.setTransferRateLimit(0xFFFFFFFFFFFF)
    turnOn("right")
    print("REACTOR IS ON!")
end

-- Wait for the cables to discharge to this percentage before kicking the gens back on
local refillZone = 75
local shutDown = false

-- This is hacked together in a hurry so things'll be quick and dirty. You see nuclear explosions scare me
local function main()
    local percent = cable.getFilledPercentage() * 100
    -- A low or zero transfer rate means the batteries aren't accepting input. That'll stall our turbine
    if masterOff or (periph.getTransferRate() <= 10 or redstone.getInput("left")) then
        periph.setTransferRateLimit(50)
        shutDown = true
        turnOff("right")
    elseif not masterOff and percent <= refillZone then
        periph.setTransferRateLimit(cable.getCapacity() * ((100 - percent) / 100))
        shutDown = false
        turnOn("right")
    end
end

local function cleanup()

end

deviceDescriptor = {
    deviceType = "NuclearRedstoneInterface", -- Used mostly for grouping
    deviceName = "Basic NRI MK.2", -- Basic Nuclear Redstone Interface Device Mark One. You think it's plug and play?
    functions = {
        -- most functions were stripped for security
        togglereactor = toggle,
    },
    variables = {
        shutdown = {
            value = shutDown, -- We need to wait for init
            valueType = "number",
            getCallback = function (self)
                -- Look I don't want to track it too hard. Also it's always accurate for end users even if I fuck up.
                self.value = shutDown
                return self.value
                end,
            modifyCallback = function (self, new) return false, "Value is Read Only." end -- denied.
        },
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