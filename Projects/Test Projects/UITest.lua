    local bedrockCore = require("BedrockAPI.BedrockCore")
    local bedrockInput = require("BedrockAPI.BedrockInput")
    local bedrockGraphics = require("BedrockAPI.BedrockGraphics")
    local bedrockUI = require("BedrockAPI.BedrockUI")

    -- Add your modules to your core instance
    local coreInstance = bedrockCore.coreBuilder:new():addModule(bedrockInput):addModule(bedrockGraphics):addModule(bedrockUI)

    -- build your core so it'll be run in the update loop
    coreInstance:build()

    local monitor = bedrockInput.GetGenericDisplayPeripheral(term)
    local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)

    local menu = bedrockUI.menuBuilder:new(DOM)
    local Obj1 = bedrockUI.menuObjectBuilder.new():setBackgroundColor("#FF0000"):setSize("50%","50%"):setParent(menu)
    local Obj2 = bedrockUI.menuObjectBuilder.new():setBackgroundColor("#00FF00"):setX("50%"):setSize("50%","50%"):setParent(menu)
    local Obj3 = bedrockUI.menuObjectBuilder.new():setBackgroundColor("#0000FF"):setY("50%"):setSize("50%","50%"):setParent(menu)
    local Obj4 = bedrockUI.menuObjectBuilder.new():setBackgroundColor("#BADEC2"):setX("50%"):setY("50%"):setSize("50%","50%"):setParent(Obj3)
    local button = bedrockUI.buttonBuilder.new():setSize("50%","50%"):setText("Detonate"):setZ(2):setBackgroundColor("#E62A2A"):setParent(menu)

    local textBox = bedrockUI.textInputBuilder.new():setSize("90%", "2px"):setX(5):setZ(999):setY(1):setParent(menu)
    local percentBox = bedrockUI.progressBarBuilder.new():setSize("90%", "2px"):setX(5):setZ(999):setY(3):setParent(menu)

    local toggleButton = bedrockUI.toggleButtonBuilder.new():setX(2):setY(7):setZ(999):setParent(menu)

    local pollRate = 1500
    local timeElapsed = 0
    local samples = 0

    -- This hook is useful because it always stays up to date with the correct dt
    coreInstance.hooks.onUpdate.addHook(function (dt)
                timeElapsed = timeElapsed + dt
                samples = samples + 1
                if timeElapsed >= pollRate then
                    Obj4:setText(string.format("FPS: %.2f", 1000 / (timeElapsed / samples)))
                    samples = 0
                    timeElapsed = 0
                end
    end)

    local terminate = false
    -- Your own main function. When it completes your program is over
    local function main()
        parallel.waitForAny(function ()
            while true do
                button:setBackgroundColor("#E62A2A")
                Obj2:setY("50%")
                os.sleep(1)
                button:setBackgroundColor("#D8D836")
                Obj2:setY("0%")
                os.sleep(1)
            end
        end,
        function ()
        while not terminate do
            os.sleep(0)
        end
        end)
    end

    bedrockInput.RegisterKeyEvent("Quit", function ()
        terminate = true
    end, function () end, function () end, false, "grave")

    -- main is for your own logic, and tick is for Bedrock's logic.
    parallel.waitForAny(bedrockCore.Tick, main)

    -- Make sure to cleanup your core to avoid resource leaks
    coreInstance:Cleanup()