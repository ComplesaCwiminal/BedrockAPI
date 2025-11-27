-- TeSoMu

-- Obtain BedrockAPI, and DFPWM parsing
local bedrockCore = require "BedrockAPI.BedrockCore"
local bedrockInput = require "BedrockAPI.BedrockInput"
local bedrockGraphics = require "BedrockAPI.BedrockGraphics"
local dfpwm = require "cc.audio.dfpwm"

-- Get Launch arguments
local launchArgs = {...}

-- Find all the speakers, and initialize 
local speakers = {peripheral.find("speaker")}
local tracks = {}
local buffer = {}
local chosenFile = ""

local settingsExists = settings.load("TeSoMu.settings")


-- Default value
local loop = true


-- Create a new core
local core = bedrockCore.coreBuilder:new()

-- Add our modules to the core, and build it
core:addModule(bedrockInput):addModule(bedrockGraphics):build()

-- Obtain our monitor in a genericized form (You know. This generic peripheral has a generic [Which is just the wrapped peripheral {Might've removed this}])
local monitor = bedrockInput.GetGenericDisplayPeripheral(term)

-- Create the DOM, and bind it to our monitor
local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)

-- Get a clean slate
monitor.clear()

-- Initialize a few important values
local listItems = {} 
local reset = false
local continue = false
local selected = 1
local playObject = nil

-- Shush speakers on startup
for i,v in ipairs(speakers) do 
    v.stop()
end

--- Sets the selections to their proper colors

local itemOffset = 0
local function selectionRerender()

    -- Set every value to the deselected color, or the selected colors
    for i,v in pairs(listItems) do
        v:setY(i + itemOffset + 1)
        if i == selected then
            v:setColors(colors.packRGB(term.nativePaletteColour(colors.black)), colors.packRGB(term.nativePaletteColour(colors.gray)))
        else 
            if i % 2 ~= 0 then
            v:setColors(colors.packRGB(term.nativePaletteColour(colors.white)), colors.packRGB(term.nativePaletteColour(colors.black)))
            else 
            v:setColors(colors.packRGB(term.nativePaletteColour(colors.white)), 0x262626)
            end
        end
    end
    
end

-- Create the variables, but don't populate them yet. We don't have enough info to yet, anyway
local volumeFill = nil
local volumeObj = nil

-- Some constants
local volumeStep = .01
local volumeMax = 1
-- Originally launch arg only, but now implemented fully. Backwards compatible with old way
if settingsExists == false then 
    settings.define("volume", {
        description = "Playback volume",
        type = "number",
        default = .33
    })
    if launchArgs[2] ~= nil then
    settings.set("volume", tonumber(launchArgs[2]))
    end
end

local volume = settings.get("volume")

--- The function for navigating up in a menu, and increasing volume.
local function navUp()
    -- If we're in the menu...
    if not continue then
        -- decrement the selection counter
        selected = selected - 1
        

        -- if we've exceeded our range...
        if selected < 1 then
            -- loop around
            selected = #listItems
        end
    
        -- rerender.
        selectionRerender()
    else
        -- if we're playing music.

        -- increase the volume
        if volume + volumeStep <= volumeMax then
            volume = volume + volumeStep
        else 
            -- clamp audio volume at 3
            volume = volumeMax
        end
        -- Set the text, and the volume fill bar.
        volumeObj:setText("Volume: " .. string.format("%.2f", (volume / volumeMax) * 100) .. "%")
        -- The orange color is to denote that the volume change hasn't applied yet
        volumeFill:setWidth((volume / volumeMax) * (monitor.width / 2)):setBackgroundColor(0xffc654)
    end
end

--- The function for navigating down in a menu, and decreasing volume.
local function navDown()
    -- If we're in the menu...
    if not continue then
        -- increment the selection counter
        selected = selected + 1 
        
        -- if we've exceeded our range...
        if selected > #listItems then
            -- loop around
            selected = 1
        end
        
        -- rerender.
        selectionRerender()
    else
        -- if we're playing music.

        -- decrease the volume
        if volume - volumeStep >= 0 then
            volume = volume - volumeStep
        else
            -- clamp audio volume at 0 
            volume = 0
        end
        -- Set the text, and the volume fill bar.
        volumeObj:setText("Volume: " .. string.format("%.2f", (volume / volumeMax) * 100) .. "%")
        -- The blue color is to denote that the volume change hasn't applied yet
        volumeFill:setWidth((volume / volumeMax) * (monitor.width / 2))
        if monitor.generic.isColor() then
            volumeFill:setBackgroundColor(0xFFC654)
        else
            volumeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.pink)))
        end
    end
end

--- The function for navigation, and volume control via scrolling
local function scrollNav(_ev, dir, x,y)
    -- Use the nav up and down functions combined with scroll direction to navigate
    if dir == -1 or dir == 0 then
        navUp()
    else 
        navDown()
    end
end

-- define the last clicks we got, and how quick you have to be for it to be a double click
local timeOfLastClick = 0
local doubleClickLeniency = 450 -- in MS

--- The function for menu navigation via clicking, or dragging
local function clickNav(_ev, button, x,y)
    y = y - itemOffset - 1

    if y <= 2 and itemOffset > 1 then
        itemOffset = itemOffset - 1
    elseif y == monitor.height and itemOffset < #listItems - monitor.height then
        itemOffset = itemOffset + 1
    end
    -- if it's a left click, and we're still in the selection menu...
    if button == 1 and not continue then
        -- ...then check if it's a double click...
        if selected == y and (os.epoch("utc") - timeOfLastClick < doubleClickLeniency) then
            -- ... if it is then continue as if you used the confirm keybind
            continue = true
            chosenFile = listItems[selected].option
        end
        -- Make sure the click isn't higher than the options
        if y > 0 then
        -- Make sure it's also not too low
        if y <= #listItems then
            -- If we're within our range, just set the selection to the click's Y.
            selected = y
        else
            -- if it is, just clamp it
            selected = #listItems
        end
        else
            -- if it is, just clamp it
            selected = 1
        end
        timeOfLastClick = os.epoch("utc")
    end
    
    selectionRerender()
end


core:registerEvent("mouse_scroll", scrollNav)
-- If we're running on a terminal....
if monitor.base.type == "term" then
    -- Enable, and register the click, and drag functions.
    core:registerEvent("mouse_click", clickNav)
    -- The drag is treated as repeatedly clicking, but stops double click logic.
    core:registerEvent("mouse_drag", function(_ev, button, x,y) timeOfLastClick = 0 clickNav(_ev, button, x,y) end)
else
    -- Otherwise, check if what was touched was our monitor, and treat that as a left click
    core:registerEvent("monitor_touch", function(_ev, name, x,y)
        if monitor.base.name == name then
            clickNav(_ev, 1, x,y)
        end
    end)    
end

-- Set the up and down navigation for both tapping, and holding the buttons.
bedrockInput.RegisterKeyEvent("Navigate Up", navUp, navUp, function() end, true, "w")
bedrockInput.RegisterKeyEvent("Navigate Down", navDown,navDown, function() end, true, "s")
bedrockInput.RegisterKeyEvent("Navigate Up", navUp, navUp, function() end, true,  "up")
bedrockInput.RegisterKeyEvent("Navigate Down", navDown,navDown, function() end, true,  "down")

-- The confirm event. Bound to enter
bedrockInput.RegisterKeyEvent("Confirm", 
function() 
    -- Set continue to true
    continue = true
    -- Decide the chosen file definitively
    chosenFile = listItems[selected].option
end, function() end, function() end, true,  "enter")

-- Register the Back / Reset key event via bedrock input. Bound to backspace
bedrockInput.RegisterKeyEvent("Reset", 
function() 
    -- Set reset to true
    reset = true
    -- If there is a play object turn it red, and make it say stopping
    -- We do this because it may take a second to return to the select screen (well it used to. not anymore, but lag)
    if playObject ~= nil then
        playObject:setText("Stopping!"):setTextColor(colors.packRGB(term.nativePaletteColour(colors.red)))
    end
    -- Stop all speakers from playing.
    for index, value in pairs(speakers) do
        value.stop()
    end
end, function() end, function() end, true, "backspace")


local fileName = ""

-- Create the decoder here
local decoder = dfpwm.make_decoder()

local playTimeFill = nil

-- Our main function. 
local function main()
    -- Under normal conditions always loop the file selection and playback states.
    while true do
        bedrockGraphics.objectBase:new():setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.black))):setPosition(1,1,-9999):setSize(monitor.width, monitor.height):setParent(DOM)
        bedrockGraphics.objectBase:new():setText("Tracks"):setPosition(1, 1, 10):setTextColor(colors.packRGB(term.nativePaletteColour(colors.white))):setSize(monitor.width, 1):setBackgroundColor(0x2F6B7F):setParent(DOM)

        -- find the files using a wildcard
        local files = fs.find("**.dfpwm")
        for i,v in pairs(fs.find("**/*.dfpwm")) do
            table.insert(files, v)
        end
        
        -- for each file found
        for i,v in pairs(files) do
            -- make sure something shows up always
            fileName = v

            -- strip it down to the file name
            if string.find(v, "/") ~= nil then
                
            for i2 in string.gmatch(fileName, "([^/]+)") do
                fileName = i2
            end -- slowly gets the last element in the list
            else
                fileName = v
            end

            local filePortions = {}
            for i2 in string.gmatch(fileName, "([^.]+)") do
                table.insert(filePortions, i2)
            end -- slowly gets the last element in the list
            table.remove(filePortions, #filePortions)
            fileName = ""
            for _,v2 in ipairs(filePortions) do
                fileName = fileName .. v2
            end 
            
            -- Create and file away the object denoting each file.
            table.insert(listItems, bedrockGraphics.objectBase:new():setText(fileName ~= "" and fileName or tostring(i)):setPosition(1, i + 1, 1):setSize(monitor.width, 1):setParent(DOM))
            -- set a hidden value to be the actual files PATH. Not just the file name
            listItems[i].option = v
        end
        if launchArgs[1] == nil then
        reset = false
        selectionRerender()
        -- Stall the actual music code until we are told to continue.
        while not continue do
            -- just sleep for a small small time step
            os.sleep(0)
            -- Quit the program if back is pressed here.
            if reset then
                return
            end
        end
        else
            reset = false
            loop = false
            chosenFile = listItems[math.random(1, #listItems)].option
        end
            -- If all else fails make sure somethings there
            fileName = chosenFile

            -- Attempt to remove the path, and just get the file name alone
            if string.find(chosenFile, "/") ~= nil then
            for i in string.gmatch(fileName, "([^/]+)") do
                fileName = i
            end -- slowly gets the last element in the list
            else
                fileName = chosenFile
            end

            local filePortions = {}
            for i in string.gmatch(fileName, "([^.]+)") do
                table.insert(filePortions, i)
            end -- slowly gets the last element in the list
            table.remove(filePortions, #filePortions)
            fileName = ""
            for _,v2 in ipairs(filePortions) do
                fileName = fileName .. v2
            end 

            -- Clear the screen
            DOM:clear()
            term.clear()

            bedrockGraphics.objectBase:new():setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.black))):setPosition(1,1,-999):setSize(monitor.width, monitor.height):setParent(DOM)

            -- Create and draw the user information
            playObject = bedrockGraphics.objectBase:new():setText("Playing!"):setPosition(1, math.ceil((monitor.height / 2) - 1), 10):setTextColor(colors.packRGB(term.nativePaletteColour(colors.green))):setSize(monitor.width, 1):setParent(DOM)
            bedrockGraphics.objectBase:new():setText("Press backspace to go back."):setPosition(1, 1, 1):setSize(monitor.width, 1):setTextColor(colors.packRGB(term.nativePaletteColour(colors.blue))):setParent(DOM)
            bedrockGraphics.objectBase:new():setText("Press up and down to change the volume."):setPosition(1, 2, 1):setSize(monitor.width, 1):setTextColor(colors.packRGB(term.nativePaletteColour(colors.blue))):setParent(DOM)
            -- Create object for showing what song is playing
            bedrockGraphics.objectBase:new():setText("Song:"):setPosition(1, monitor.height - 2, 1):setSize(monitor.width, 1):setTextColor(0x666666):setParent(DOM)
            bedrockGraphics.objectBase:new():setText(fileName):setPosition(1, monitor.height - 1, 1):setSize(monitor.width, 1):setParent(DOM)
            -- play time Fill bar. The first is the BG, the second the fill
            bedrockGraphics.objectBase:new():setPosition(2, monitor.height, 1, 0):setSize(monitor.width - 2, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.gray))):setParent(DOM)
            playTimeFill = bedrockGraphics.objectBase:new():setPosition(2, monitor.height, 3):setSize(1, 1):setParent(DOM)

            -- compute the songs length in seconds from its file size (approximate)
            local songLength = (fs.getSize(chosenFile) * 8 / 48000)
            -- convert it into a MM:SS notation
            local computedLength = os.date("%M:%S", songLength)
            -- get when the song has started to know how far in we are.
            local startTime = os.epoch("utc")
            -- Create the time object, and populate it with the calculations just above
            local timeObj = bedrockGraphics.objectBase:new():setText("0:00 /" .. computedLength):setPosition(1, math.ceil((monitor.height / 2)), 5):setSize(monitor.width, 1):setTextColor(colors.packRGB(term.nativePaletteColour(colors.white))):setParent(DOM)
            -- Create an object that's text tells you the exact volume percentage
            volumeObj = bedrockGraphics.objectBase:new():setPosition(1, math.ceil((monitor.height / 2) + 1), 1, 1):setSize(monitor.width, 1):setTextColor(colors.packRGB(term.nativePaletteColour(colors.yellow))):setParent(DOM)
            volumeObj:setText("Volume: " .. string.format("%.2f", (volume / volumeMax) * 100) .. "%")
            -- Volume Fill bar. The first is the BG, the second the fill
            bedrockGraphics.objectBase:new():setPosition(monitor.width / 4, math.ceil((monitor.height / 2) + 2), 0):setSize(monitor.width / 2, 1):setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.gray))):setParent(DOM)
            volumeFill = bedrockGraphics.objectBase:new():setPosition(monitor.width / 4, math.ceil((monitor.height / 2) + 2), 3):setSize((volume / volumeMax) * (monitor.width / 2), 1):setParent(DOM)
            if monitor.base.functions.isColor() then
                volumeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.green)))
                playTimeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.green)))
            else
                volumeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.white)))
                playTimeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.white)))
            end
            
            -- Set up play back the buffer through all attached speakers
            for i,v in ipairs(speakers) do 
                -- We use this to have a track playback function for each speaker. They're identical.
                table.insert(tracks, function ()
                        -- Wait until playback is done OR the instant that reset is true
                        parallel.waitForAny(function()
                        -- until audio fails pull the buffer empty event, and add more audio after
                        while not v.playAudio(buffer,  (volume ^ 3) * 3) do
                            if not reset then

                                parallel.waitForAny(function ()
                                    -- This is mostly just for an edge case where you clear the speakers the exact frame that the buffer is supposed to fill.
                                    os.sleep(3) -- A bit longer than our buffer maxes out at.
                                end, function ()
                                    
                                    os.pullEvent("speaker_audio_empty")
                                
                                end)
                            end
                            if monitor.base.functions.isColor() then
                                volumeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.green))) -- Set it to green to indicate that the volume has changed
                            else
                                volumeFill:setBackgroundColor(colors.packRGB(term.nativePaletteColour(colors.white))) -- Set it to white to indicate that the volume has changed
                            end
                        end
                        end, function ()
                            -- A short circuit
                            while not reset do
                                os.sleep(0)
                            end
                            v.stop()
                        end)
                end)
            end 
        -- Loop the song until reset is true
        while not reset do
            startTime = os.epoch("utc")
            parallel.waitForAny(function ()
                
                -- Read all the lines in the file, and play back each one as you get it.
                -- This can cause buffer underflow if IO is ungodly slow. Beware    
                for input in io.lines(chosenFile, 16 * 1024) do
                    if not reset then
                    -- Decode the audio from the file, and place it in the buffer
                    buffer = decoder(input)
                    -- Play each track in parallel.. Probably. parallel job to prioritize, not mine.
                    parallel.waitForAll(table.unpack(tracks))
                    -- Avoid the watchdogs wrath
                    os.sleep(0)
                    end
                end

                -- If we're not supposed to loop set reset to true so the while loop ends
                if not loop then
                    reset = true
                end
                if not reset then
                    parallel.waitForAny(function ()
                        -- This is mostly just for an edge case where you have no speakers
                        os.sleep(2.5) -- A bit longer than our buffer maxes out at.
                    end, function ()
                                    
                    os.pullEvent("speaker_audio_empty")
                    end)
                end
            end, function () 
                -- This method of timer only works because the other side of the parallel ends instead.
                
                -- Doing it this way prevents desync from tick rate fluctuation.. mostly

                -- For the rest of time...
                while true do 
                        -- Get the current time in the song in seconds (it'll be small since the inputs are ms)
                        local curTime = (os.epoch("utc") - startTime) / 1000
                        -- Set the time text to the current play time
                        timeObj:setText(os.date("%M:%S", curTime) .. " /" .. computedLength)
                        --if math.floor(curTime) % 2 ~= 0 then
                            if not playObject.enabled then
                                playObject:enable()
                            else
                                playObject:disable()
                            end
                        --+-end
                        -- If the fill of the bar exists...
                        if playTimeFill ~= nil then
                            -- Set it's width to the songs playback percentage of it's maximum size
                            playTimeFill:setWidth((curTime / songLength) * (monitor.width - 2))
                                -- Why did I name this maymsa
                                local maymsa = math.min(1, math.max(0, curTime / songLength))
                                local t = maymsa < 0.5 and 2*maymsa*maymsa or -1 + (4 - 2*maymsa)*maymsa
                                -- Probably move these
                                
                                local startRGB = {colors.unpackRGB(0xCC4C4C)}
                                local endRGB = {colors.unpackRGB(0x57A64E)}
                                local curRGB = {}

                                for i in ipairs(startRGB) do
                                    table.insert(curRGB, startRGB[i] + (endRGB[i] - startRGB[i]) * t)
                                end

                                playTimeFill:setBackgroundColor(colors.packRGB(table.unpack(curRGB, 1, 3)))
                        end
                    -- wait one second. Probably
                    os.sleep(1)
                    
                end
            end)
        end

        -- Stop speakers after playback ends naturally.
        for i,v in ipairs(speakers) do 
            v.stop()
        end

        -- Yes I know this is a bad solution. I just plan to have a bedrock solution,
        -- so I don't want to make my own thing

        -- If theres a launch arg in slot one..
        if launchArgs[1] == nil then
            -- assume it's about continue, and set it to false
            continue = false
        end
        -- clear out everything that could be dirty
        tracks = {}
        buffer = {}
        listItems = {} 
        chosenFile = ""
        -- if we're not on shuffle..
        if launchArgs[1] == nil then
            -- Clear the DOM, and get ready to go back to the selection screen
            DOM:clear()
            term.clear()
        end
        playObject = nil
    end
end

-- Run our code in parallel with bedrockCores ticks (I need to rename tick, but then stuff'd break)
parallel.waitForAny(bedrockCore.Tick, main)

settings.set("volume", volume)
settings.save("TeSoMu.settings")
settings.getDetails("volume")

core:Cleanup()
