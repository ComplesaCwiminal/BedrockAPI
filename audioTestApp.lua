    local bedrockCore = require("BedrockAPI.BedrockCore")
    local bedrockInput = require("BedrockAPI.BedrockInput")
    local bedrockGraphics = require("BedrockAPI.BedrockGraphics")
    local bedrockSound = require("BedrockAPI.BedrockSound")

    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new():addModule(bedrockInput):addModule(bedrockGraphics):addModule(bedrockSound)

    -- build your core so it'll be run in the update loop
    coreInstance:build()


    -- Your own main function. When it completes your program is over
    local function main()
        -- Create a monitor to render to; Set term to a wrapped peripheral for another monitor
        local monitor = bedrockInput.GetGenericDisplayPeripheral(term)

        -- Create a new DOM to render to and set the monitor 
        local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)
        
        -- A background object to stop buffer bleed.
        bedrockGraphics.objectBase:new():setPosition(1,1):setSize(monitor.width, monitor.height, -9999):setBackgroundColor(0):setParent(DOM)
        
        -- A Hello World Object! Make sure it's on the DOM
        local hello = bedrockGraphics.objectBase:new():setParent(DOM)

        -- Set it's position and text align, then it's hello world!
        hello:setPosition(1,1):setStyle("textAlign", "topleft"):setText("Hello World!")
        
        local b, a = bedrockSound.CreateTrack(1,"pcm",1)

        bedrockSound.Play()

        local t, dt = 0, 2 * math.pi * 220 / 48000
        for i = 1, 128 * 1024 do
            a:pushData(math.floor(math.sin(t) * 127))
            t = (t + dt) % (math.pi * 2)
        end
        -- Methods can be chained infinitely.
        bedrockGraphics.objectBase:new():setPosition(1,monitor.height):setStyle("textAlign", "topleft"):setText("Press any key to continue"):setParent(DOM)
        os.pullEvent("key") -- Base CC event pull because it's blocking.
    end
    
    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()
local buffer = {}

speaker.playAudio(buffer)