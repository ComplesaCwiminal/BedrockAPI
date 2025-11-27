-- THIS PROJECT IS OUT OF DATE WITH THE MODERN BEDROCKAPI: RESOLVED; REMOVE

-- God why did we ever not support relative positioning

local bedrockCore = require "BedrockAPI.BedrockCore"
local bedrockGraphics = require "BedrockAPI.BedrockGraphics"
local bedrockInput = require "BedrockAPI.BedrockInput" --Keep forgetting that input is actually IO. It's a misnomer. lmao

local core =  bedrockCore.coreBuilder:new()
core:addModule(bedrockInput):addModule(bedrockGraphics):build()

local monitor = bedrockInput.GetGenericDisplayPeripheral(peripheral.find("monitor"))
pcall(monitor.functions.setTextScale, .75)
pcall(term.setTextScale, .75)

local BGColor = 0x0
local BGFrom = 0x727284
local BGTo = 0x868693
local transitionTime = 15.0

local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)
local bgObj = bedrockGraphics.objectBase:new():setSize(monitor.width, monitor.height):setPosition(1,1,0):setBackgroundColor(0x868693):setText(""):setParent(DOM)
-- What do I want for this screen. It's just vfx
-- Lets see... (why am I having a conversation with myself)
-- 1.) Tube integrity 2.) I/Ex pressure 3.) O2 levels 4.) Entity Name 5.) I/Ex Tube temp 6.) I/Ex atmo comp. 7.) Is entity present?
local internalReadings = {}
local externalReadings = {}
local blanketReadings = {}
local function registerReadingRange(category, name, min, max, suffix)
    local reading = {
        isStatic = false,
        readingName = name,
        readingMin = min,
        readingMax = max,
        readingSuffix = suffix
    }
    table.insert(category, reading)
end 
local function registerStaticReading(category, name, value)
        local reading = {
        isStatic = true,
        readingName = name,
        readingValue = value
    }
    table.insert(category, reading)

end

-- This is the only thing that you'd need to change.
local entityName = "Empty"
local entityPresent = false

-- The rest of these are meaningless readings for atmospheric storytelling purposes.
registerStaticReading(internalReadings, "Internal Readings", "")
registerReadingRange(internalReadings, "Integrity: ", 99.9, 100, "%")
registerReadingRange(internalReadings, "O2: ", 0.0, 0.15, "%")
registerReadingRange(internalReadings, "Pressure: ", 1, 1.25, " atm.")
registerReadingRange(internalReadings, "Temp.: ", 15.0, 30.0, " \176F")
registerStaticReading(internalReadings, "Main Gas: ", "")
registerReadingRange(internalReadings, "Argon: ", 99.85, 100.0, "%") -- I always choose argon as my inert gas because that's the gas from the scp 1762
registerStaticReading(externalReadings, "External Readings", "")
registerReadingRange(externalReadings, "Pressure: ", 1, 3, " atm.") -- What are you doing to get three atmospheres of pressure down here. uhhh. science? 
registerReadingRange(externalReadings, "Temp.: ",  65.0, 75.0, " \176F") -- In the words of help wanted, "A perfect 72 degrees. See you next time."
registerStaticReading(externalReadings, "Main Gas: ", "")
registerReadingRange(externalReadings, "Oxygen: ", 21, 25, "%")
registerReadingRange(externalReadings, "Nitrogen: ", 75, 78, "%")
registerStaticReading(blanketReadings, entityName, "")
registerStaticReading(blanketReadings, entityPresent and "ENTITY PRESENT" or "NO ENTITY PRESENT", "")

local readingObjectPair = {}
local tube1X = 2
local tube1Y = 2

local tube2X = math.ceil(monitor.width / 2) + 7
local tube2Y = 2
local blanketX = 2
local blanketY = #internalReadings * 2 + 5
local function computeReading(reading, readingObject)
            if not reading.isStatic then
        local range = reading.readingMax - reading.readingMin
        local randomFloat = math.random()
        local readingValue = reading.readingMin + (randomFloat * range)
                readingObject:setText(string.format("%.2f", readingValue)  .. reading.readingSuffix)
            elseif reading.readingValue ~= nil then
                readingObject = readingObject:setText(reading.readingValue)
            end
            return readingObject
end
local function main()
        local tubeObj = bedrockGraphics.objectBase:new():setText(""):setSize(monitor.width / 2 - 8, #internalReadings * 2 + 2):setPosition(tube1X, tube1Y, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.blue))):setParent(DOM)

        local offset = 0
        for i,v in pairs(internalReadings) do
            for i2,v2 in pairs(v) do
                print(v2)
            end
            bedrockGraphics.objectBase:new():setText(v.readingName):setPosition(1, ((i * 2) - offset), 1):setSize(monitor.width / 2 - 8, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.blue))):setParent(tubeObj)
            local readingObject = nil
            
            if not v.isStatic or v.readingValue ~= nil then
                if v.readingValue ~= "" then
                readingObject = bedrockGraphics.objectBase:new():setPosition(1, ((i * 2) - offset) + 1, 1):setSize(monitor.width / 2 - 8, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.blue))):setParent(tubeObj)
                    computeReading(v, readingObject)
                else 
                    offset = offset + 1
                end
            end

            if readingObject ~= nil then
                table.insert(readingObjectPair, {v, readingObject})
            end

        end
        local tubeObj2 = bedrockGraphics.objectBase:new():setText(""):setSize(monitor.width / 2 - 8, #internalReadings * 2 + 2):setPosition(tube2X, tube2Y, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.orange))):setParent(DOM)

        offset = 0
        for i,v in pairs(externalReadings) do
            for i2,v2 in pairs(v) do
                print(v2)
            end
            bedrockGraphics.objectBase:new():setText(v.readingName):setPosition(1, ((i * 2) - offset), 1):setSize(monitor.width / 2 - 8, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.orange))):setParent(tubeObj2)
            local readingObject = nil
            
            if not v.isStatic or v.readingValue ~= nil then
                if v.readingValue ~= "" then
                readingObject = bedrockGraphics.objectBase:new():setPosition(1, ((i * 2) - offset) + 1, 1):setSize(monitor.width / 2 - 8, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.orange))):setParent(tubeObj2)
                    computeReading(v, readingObject)
                else 
                    offset = offset + 1
                end
            end

            if readingObject ~= nil then
                table.insert(readingObjectPair, {v, readingObject})
            end

        end
        local blanketObj = bedrockGraphics.objectBase:new():setText(""):setSize(monitor.width - 2, (#blanketReadings * 2) + 1):setPosition(blanketX, blanketY, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.gray))):setParent(DOM)

        for i,v in pairs(blanketReadings) do
            bedrockGraphics.objectBase:new():setText(v.readingName):setPosition(1, (i * 2), 1):setSize(monitor.width - 2, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.gray))):setParent(blanketObj)
        end
    while true do
        os.sleep(math.random() * 5)
        for index = 1, math.random(1, #readingObjectPair) do
            local value = readingObjectPair[math.random(1, #readingObjectPair)]
            computeReading(value[1], value[2])
        end
    end
end

local timeElapsed = 0

local function transitionColor()
    while true do
        timeElapsed = timeElapsed + (core.DeltaTime / 1000)
        if timeElapsed >= transitionTime then
            timeElapsed = 0
        end
        local normalizedTime = timeElapsed / transitionTime < 0.5 and timeElapsed or timeElapsed / 2
        local maymsa = math.min(1, math.max(0, normalizedTime / (transitionTime) * 2))
        local t = maymsa < 0.5 and 2*maymsa*maymsa or -1 + (4 - 2*maymsa)*maymsa
        -- Probably move these
        
        local startRGB = timeElapsed <= transitionTime / 2 and {colors.unpackRGB(BGFrom)} or {colors.unpackRGB(BGTo)}
        local endRGB = timeElapsed <= transitionTime / 2 and {colors.unpackRGB(BGTo)} or {colors.unpackRGB(BGFrom)}
        local curRGB = {}

        for i in ipairs(startRGB) do
            table.insert(curRGB, startRGB[i] + (endRGB[i] - startRGB[i]) * t)
        end

        bgObj:setBackgroundColor(colors.packRGB(table.unpack(curRGB)))
        os.sleep(0)
    end
end

parallel.waitForAny(main, transitionColor, bedrockCore.Tick)
BedrockCore.Cleanup()