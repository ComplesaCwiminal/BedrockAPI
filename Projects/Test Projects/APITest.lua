    -- Bedrock API no longer uses globals so these are needed. It was a security choice. Shared state is done via Core
    local bedrockCore = require("BedrockAPI.BedrockCore")
    local bedrockInput = require("BedrockAPI.BedrockInput")
    local bedrockGraphics = require("BedrockAPI.BedrockGraphics")
    --local bedrockUI = require("BedrockAPI.BedrockUI")
    local terminate = false
    local core = bedrockCore.coreBuilder:new()

    -- Hey guys. I know I haven't uploaded in a while. During the wait I've been doing a lot of self reflections on all the claims made about me.
    -- I wanted to say that many of the claims made about me were false, but I'm not going to pretend that nothing happened.
    -- I've heard your feedback, and I understand many of the criticisms made. My intentions have always been pure, and I truly value everyone
    -- in the community. I believe that during these times we must double down and put as much effort as possible into making
    -- things right, and to keep providing wonderful things for everyone to enjoy. I'm sorry that many of you interpreted my actions in that way.
    -- Moving forward I promise to be more careful with my actions, and how I conduct myself. I was under a lot of pressure and didn't consider how
    -- my actions looked to others. I'm sorry that what I said was unclear, and subject to misinterpretation. Thanks for staying by my side, and thanks for not being swayed.

        -- Side note there are no claims, no feedback, or others criticising me. So uhhh. Why did I write this. This is a fake apology.

    term.clear()

    pcall(term.current().setTextScale, 0.5)

    core:addModule(bedrockInput):addModule(bedrockGraphics)--[[:addModule(bedrockUI)]]:build()


    bedrockInput.RegisterKeyEvent("TEST NAME", function() --[[originally an error not a print.]] print("Ow.") end, function() print("--") end, function() print("Termibate") terminate = true end, "grave")

    local monitor = bedrockInput.GetGenericDisplayPeripheral(term)

    local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)
    
    --bedrockUI.scrollBarBuilder:new():computeHandleSize():setParent(bedrockUI.menuBuilder:new(DOM):setPosition(1,1,-99999):setSize(monitor.width, monitor.height)):setSize("100%", "100%")

    local object1 = bedrockGraphics.objectBase:new():setPosition(17, 15, 8):setBackgroundColor(0xFFC654):setText("Hey there big boy.")
    local object2 = bedrockGraphics.maskObject:new():setText("OBJECTS???"):setPosition(5, 5, 7):setSize(monitor.width - 8, monitor.height / 3):setBackgroundColor(0x00ff00):setTextColor(0x101010)
    local object3 = bedrockGraphics.objectBase:new():setText("Gotta wonder the performance hit"):setPosition(2, 2, 10)
    local gayObject = bedrockGraphics.objectBase:new():setZ(-10):setSize(monitor.width, monitor.height):setTextColor(0x101010):setBackgroundColor(0xFFFFFF):setParent(DOM)
    local objectTooMany = bedrockGraphics.objectBase:new():setText("Hey look! General relativity. Wait no."):setPosition(14, 6, 999):setSize(30, 1):setParent(object2)
    local object4 = bedrockGraphics.objectBase:new():setText("FPS: 0"):setPosition(1, 1, 999):setTextColor(0xFFFFFF):setStyle("textAlign", "topleft"):setParent(gayObject)
    object1:setParent(DOM)
    object2:setParent(DOM)
    object3:setParent(gayObject)

    -- This hook is useful to make sure a reconected monitor is still scaled
    monitor.hooks.onResize.addHook(function ()
        pcall(term.current().setTextScale, 0.5)
        object2:setSize(monitor.width - 8, monitor.height / 3)
        gayObject:setSize(monitor.width, monitor.height)
    end)

    local pollRate = 1500
    local timeElapsed = 0
    local samples = 0
    
    -- This hook is useful because it always stays up to date with the correct dt
    core.hooks.onUpdate.addHook(function (dt)
                timeElapsed = timeElapsed + dt
                samples = samples + 1
                if timeElapsed >= pollRate then
                    object4:setText(string.format("FPS: %.2f", 1000 / (timeElapsed / samples)))
                    samples = 0
                    timeElapsed = 0
                end
    end)

    -- Basic hook test. 
    local iter = 0
    bedrockGraphics.moduleDefinition.hooks.OnRenderFrameEnd.addHook(function ()
        object2:setText("OBJECTS??? " .. (multishell ~= nil and multishell.getCurrent() or "N/A") .. "\n Monitor: " .. monitor.base.name .. ", " .. monitor.base.type .. "\n" .. iter .. "\n W: " .. monitor.width .. " H: " .. monitor.height .. "\nBuffer: " .. (monitor.buffers[1].isVisible() and 1 or 2))
        iter = iter + 1
    end)

    -- This is a nightmare stress test for our graphics test. Uhh trust me it doesn't survive. (Well the colors don't) (gotta know your limits, ey?)
    --[[
    for i = 2, monitor.width - 1 do
        local value = i / monitor.width
        local color = colors.packRGB(value, value, value)
        bedrockGraphics.objectBase:new():setPosition(i, 3, 999):setSize(1,1):setBackgroundColor(color):setParent(DOM)
    end]]

    local function main()
        local rgbVals = {0,0, 1}
        local prevIndex = 3
        local curIndex = 1
        
        local loopedFunc = function(totalTime) end
        
        -- Fun fact. 50 or less means once per frame UNTIL you boost the tick rate.
        local iterRate = 16

        -- A timer may go over it's allotted time. Use total time to scale appropriately.
        loopedFunc = function (totalTime)

            local scrollSpeed = 0.01
            local calcedScrollSpeed = scrollSpeed * (totalTime / iterRate) -- that division should always produce 1 or higher.
            rgbVals[prevIndex] = rgbVals[prevIndex] - calcedScrollSpeed > 0 and rgbVals[prevIndex] - calcedScrollSpeed or 0
            rgbVals[curIndex] = rgbVals[curIndex] + calcedScrollSpeed

            if rgbVals[curIndex] >= 1 then
                rgbVals[curIndex] = 1
                prevIndex = curIndex
                curIndex = curIndex + 1
                
                if curIndex > #rgbVals then
                    curIndex = 1
                end
            end
            
            local color = colors.packRGB(table.unpack(rgbVals))
            local colorText = ""
            for i, v in ipairs(rgbVals) do
                colorText = colorText .. v .. ", "
            end
            gayObject:setBackgroundColor(color):setText(colorText)
            core:queueTimer(iterRate, loopedFunc)
    end


    -- Only bother with the timer if we're in color
    if monitor.generic.isColor() then
        core:queueTimer(iterRate, loopedFunc)
    end

        parallel.waitForAny(function ()
        while true do
            object2:setPosition(5, 7)
            object1:setPosition(17, 15)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(18, 15)
            os.sleep(.125)
            object2:setPosition(5, 5)
            object1:setPosition(19, 15)
            object3:setPosition(25, 20)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(20, 16)
            os.sleep(.125)
            object2:setPosition(5, 7)
            object1:setPosition(19, 16)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(19, 16)
            os.sleep(.125)
            object2:setPosition(5, 5)
            object1:setPosition(18, 16)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(17, 16)
            os.sleep(.125)
            object2:setPosition(5, 7)
            object1:setPosition(17, 15)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(18, 15)
            os.sleep(.125)
            object2:setPosition(5, 5)
            object1:setPosition(19, 15)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(20, 16)
            os.sleep(.125)
            object2:setPosition(5, 7)
            object1:setPosition(19, 16)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(19, 16)
            os.sleep(.125)
            object2:setPosition(5, 5)
            object1:setPosition(18, 16)
            os.sleep(.125)
            object2:setPosition(5, 6)
            object1:setPosition(17, 16)
            object3:setPosition(30, 10)
            os.sleep(.125)
        end
        end,function ()
            while not terminate do
                os.sleep(0)
            end
        end)
    end
    parallel.waitForAny(bedrockCore.Tick, main)
    core:Cleanup()
    