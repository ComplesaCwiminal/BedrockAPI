-- Stupid Simple Passworder is a spiritual successor to passworder.. duh.
-- Planned features list
-- Headed mode 
    -- GUI Interface!
-- Wireless Password Input
    -- Toggleable Wireless Connectivity
    -- Range Limits
    -- Rate Limits
    -- Configurable Port 
-- LabWare Integration (Potentially)
    -- Can report the lock state
    -- Can report the time of the last login
    -- Can report the time remaining on it's lockout
    -- Requires to be logged into before reporting anything.
    -- Sessions short, and require a keep alive.
-- Master Login
    -- Used to change configurations
    -- Only way to quit the application
    -- Separate password to normal
-- Configurable password(s)
-- Configurable output (ergo ping on success, redstone on success, side etc)
-- (partially) Encrypted Filesystem
-- Startup App

local bedrockCore = require("BedrockAPI.BedrockCore")
local bedrockInput = require("BedrockAPI.BedrockInput")
local bedrockGraphics = require("BedrockAPI.BedrockGraphics")
local bedrockUI = require("BedrockAPI.BedrockUI")

-- Add your modules to your core instance
local coreInstance = bedrockCore.coreBuilder:new():addModule(bedrockInput):addModule(bedrockGraphics):addModule(bedrockUI)

-- build your core so it'll be run in the update loop
coreInstance:build()


local configLocation = ""
local monitor = bedrockInput.GetGenericDisplayPeripheral(term)
local DOM = bedrockGraphics.domBuilder:new():addMonitor(monitor)

-- Who doesn't love a good white background? Eyes? Nahhh, Loser.
local sceneGraph = bedrockUI.menuBuilder:new(DOM):setBackgroundColor(0xFFFFFF):setTextColor(0x222034)

-- Creates a small dismissable popup that blocks input.
local function createPopup(heading, body, options , ...)
    -- Pack them into a table
    options = {options , ...}
    -- If that table is empty (no arguments given) then default to an 'ok' prompt
    options = #options > 0 and options or {"Ok"}
    
    local popup = {
        heading = heading,
        body = body,
        options = {}
    }

    -- TODO
    -- Should block clicks, and being -1 should make it invisible. Might wanna make sure it's onclick consumes click events
        -- Later, okay?
    local blocker = bedrockUI.menuObjectBuilder.new():setBackgroundColor(-1):setSize("100%", "100%"):setZ(9999):setParent(sceneGraph)
    -- The panel where things are stored, and objects are parented.

    local popupPanel = bedrockUI.menuObjectBuilder.new():setBackgroundColor("--light"):SetZ(2):setParent(blocker)
    -- Set the text, fill the available space.
    local popupHeading = bedrockUI.menuObjectBuilder.new():setSize("100%", "1px"):SetZ(2):setParent(popupPanel):setText(heading)
    local popupBody = bedrockUI.menuObjectBuilder.new():setSize("100%", "eval(100% - 4px)"):setY(2):SetZ(2):setParent(popupPanel):setText(body)
    
    return popup
end

local function startInitialSetup()
    if fs.exists(configLocation) then
        error("Trying to run initial setup twice?")
    end

    -- This menuObject acts like a div to hold child objects
    local setupScreen = bedrockUI.menuObjectBuilder:new():setSize("100%", "100%"):setParent(sceneGraph)

    -- A simple introduction interface.
    local helloPanel = bedrockUI.menuObjectBuilder:new():setSize("100%", "100%"):setParent(setupScreen):disable()
    local helloText = bedrockUI.menuObjectBuilder:new():setSize("100%", "5px"):setY("2px"):setParent(helloPanel):setText(
    "Welcome to Stupid Simple Passworder! \n" ..
    "Stupid Simple Passworder is a simple password input terminal designed to be simple to use! \n" ..
    "Let's get you started on this simple guided setup for your new password terminal!"
    )
    local hPContinueButton = bedrockUI.buttonBuilder:new():setPosition("eval(50% - 3.5px)", "eval(100% - 1px)"):setSize("5px", "1px"):setText("Continue"):setParent(helloPanel)
    
    -- Wait until the panel is built to enable it
    helloPanel:enable()

    local configPanel = bedrockUI.menuObjectBuilder:new():setSize("100%", "100%"):setParent(setupScreen):disable()

    hPContinueButton:addOnClick(function ()
        helloPanel:disable() -- Disable the panel
        configPanel:enable() -- Enable the next
    end)

end

local function main()
    if fs.exists(configLocation) then
        
    else
        local cfgPpu = createPopup("No config?",
        "Your config file is missing! \nIf this was intentional continue, otherwise exit now and contact an administrator.",
        "Continue", "Quit")

        -- Populate the option's actions
        cfgPpu.options[2].onClick = function ()
            os.shutdown() -- Shutdown for safety
        end
        -- Continue option
        cfgPpu.options[1].onClick = function ()
            startInitialSetup()
        end
    end
end

-- main is for your own logic, and tick is for Bedrock's logic.
parallel.waitForAny(bedrockCore.Tick, main)

-- Make sure to cleanup your core to avoid resource leaks
coreInstance:Cleanup()