    local bedrockCore = require("BedrockAPI.BedrockCore")

    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new()

    -- build your core so it'll be run in the update loop
    coreInstance:build()


    -- Your own main function. When it completes your program is over
    local function main()
        local thread = coreInstance:addThread(function ()
            rednet.receive(nil, 3)
        end)

        thread.await()
        
        os.pullEvent("key") -- Base CC event pull because it's blocking.
    end
    
    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()