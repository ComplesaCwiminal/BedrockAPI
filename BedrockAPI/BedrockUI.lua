--[[+----------------------------------------------------------+
    |                       UI MODULE                          |
    |                    +------------+                        |
    |          What this module handles: Menu objects,         |
    |                      HTML and CSS                        |
    |                      Description:                        |
    |  This module is designed to be an interactive interface  |
    |  for bedrock Graphics. In essence this is the real HTML  |
    |  and CSS of computercraft. I know. I'm sorry             |
    +----------------------------------------------------------+]]
--[[


Structure
    {Monitor Name} : {
        Object = (Monitor object)
        Menus
    }
]]

local BedrockGraphics = {}

local BedrockInput = {}

local coreInstance = {}

local BedrockUI = {}

local monitors = {}

-- This is used to handle clicks, and the like.
local trackedUIElements = {}

    local doubleClickLeniency = 250 -- in MS.
    local lastClickTime = 0
    local lastClickType = 0
    local lastClickObj = nil

    local mouseButtonsDown = {}

    local function calculateClickedObject(x,y)
        -- TODO.
    end
    -- A lot of this is mostly just to manage focus. Focus is a hard topic...
    local function handleMouseClick(_ev, button, x,y)

        -- Prevent double clicks from being registered if they take too long or aren't the same click type
        if lastClickType == button and lastClickTime - os.epoch("utc") <= doubleClickLeniency then
            -- double click logic. TODO. Obviously.
        end
        
        lastClickTime = os.epoch("utc")
        lastClickType = button
    end

    local function handleMouseUp()
        -- Can't wait to make animations with this. (lying)
    end
    local function handleDrag(_ev, button, x,y)
        -- Click and drag support? Only if you want that.
    end

    local function handleMonitorTouch(_ev, monitor, x, y)
        -- So what counts as a drag on a monitor? It's unclear.
    end

    local function handleScroll(_ev, dir, x, y)
        -- Focus? no.
    end

    -- I love how I include _ev, but it's rarely ever used. Dev choice I guess, but in an opt in system like this you know what events it could be. It won't really be a surprise when you get them.
        -- Still it has a use. I know the use. I'm just nitpicky



    --- Set the double click leniency (Which is how fast two clicks have to be grouped together before we fire a double click event)
    local function setDoubleClickLeniency(ms)
        doubleClickLeniency = ms
        lastClickTime = 0
        lastClickType = 0
    end

    -- These are nav structures that are typically keyboard centric.
    -- You'll normally only keyboard navigate on the highest open menu.
    local function navUp()

    end

    local function navDown()

    end

    local function navRight()

    end

    local function navLeft()
         
    end

    local function addNavKey(navType, key)

    end

    local function removeNavKey(navType, addNavKey)

    end
    -- Turns a complex unit (eg. %, vw, vh, etc.) into a raw pixel value. 
    local function computeNumericalUnit(object, givenNum, valueName)
        if type(givenNum) == "string" then
            -- There should not be three or more matches
            local num, unit, err = givenNum:match("^(-?%d+%.?%d*)%s*(.*)$")
 
            if err then
                return false, "unit parsing failed!"
            end

            num = tonumber(num)

            if type(num) ~= "number" then
                return givenNum
            end

            -- Can I please have switch statements? Please?
                

            -- The forbidden units. Returned as if they were specifying pixels, because they're too small or I'm to scared to calculate them
            if unit == "cm" or unit == "mm" or unit == "in" then
                return num
            elseif unit == "pt" then
                return math.ceil(num / 12)
            -- They said this would be relative. They lied.
            elseif unit == "pc" or unit == "em" or unit == "ex" or unit == "ch" or unit == "rem" then
                return num
            elseif unit == "vw" then
                -- fun fact. You need a viewport to use this unit. I know. Surprising
                if object.monitor ~= nil then
                    return num *(object.monitor.width * 0.01)
                end
                -- Try not to crash in user space, ey?
                return num, false
            elseif unit == "vh" then
                if object.monitor ~= nil then
                    return num *(object.monitor.height * 0.01)
                end
                
                return num, false
            
            elseif unit == "vmin" then
                if object.monitor ~= nil then
                    local vmin = object.monitor.width < object.monitor.height and object.monitor.width or object.monitor.height
                    return num *(vmin * 0.01)
                end
                return num, false
            elseif unit == "vmax" then
                if object.monitor ~= nil then
                    local vmax = object.monitor.width > object.monitor.height and object.monitor.width or object.monitor.height
                    return num *(vmax * 0.01)
                end
            elseif unit == "%" then
                if object.parent ~= nil then
                if object.parent.computedStyle ~= nil and object.parent.computedStyle[valueName] then
                    return num * (object.parent.computedStyle[valueName] * 0.01)
                end

                -- I did not realize I was signing up for recursion. Oops.
                return num * (computeNumericalUnit(object.parent, object.parent.style[valueName], valueName) * 0.01)
                else
                    -- Oh god theres no absolute value. Guess it's viewport
                    if valueName == "width" or valueName == "w" or valueName == "x" then
                        if object.monitor ~= nil then
                            return num *(object.monitor.width * 0.01)
                        end
                    elseif valueName == "height" or valueName == "h" or valueName == "y" then
                        if object.monitor ~= nil then
                            return num *(object.monitor.height * 0.01)
                        end
                    end
                    -- Okay so we have NOTHING. Absolutely nothing.
                    return num, false
                end
            end
            return num, false
        end

        return givenNum
    end

    -- We internally need our colors to be a number. eg. 0x0f2fac
    local function parseColor(aColor) 
        if type(aColor) == "string" then
            -- Hex
            if string.sub(aColor, 1,1) == "#" then
                aColor = tonumber("0x" .. string.sub(aColor, 2, #aColor))
            else
                return false, "Color is not a valid format."
            end
        end 

        if type(aColor) ~= "number" then
            return false, "Color is not able to be parsed."
        else
            return aColor
        end
    end

    --- A helper function to make something similar to an inheritence model
    --- @param object table
    --- @param inherited table
    local function inheritFromInstance(parent, object, inherited)

        -- This is assumedly an pattern
            -- This is hard to explain, but you need to trust me that it's VERY important, and is completely intentional

        --Yes we want it instantiated. No I don't want to explain it here
            -- Check the docs for more info on this topic.

        local copy = {}
        -- perform a shallow copy because we don't want to reflect the __index we're about to do in the real thing
            -- I think copy = self wouldn't work because they'd technically be the same table. So here we are
        for i,v in pairs(parent) do
            copy[i] = v
        end
        local objectInstance = inherited:new()
        setmetatable(copy, {__index = objectInstance})
        copy.__index = objectInstance
        
        setmetatable(object, {__index = copy})

        -- This just allows you to get your base/super or whatever. You need it, trust me.
        object.__index = copy
        
        return object
    end

    --Entity Component System? Yeah I don't know what that means, but I hope you find what you're looking for.

    -- Menus and menu objects are seperate, but in theory almost everything will derive from this object
    MenuObjectBuilder = {}

    function MenuObjectBuilder:new()
        local builder = {
            -- These are post unit compute. They're stored in styles until unit compute
            x = 1,
            y = 1,
            z = 1,
            w = 0,
            h = 0,
            style = {},
            computedStyle = {},
            -- TEMP COLORS
            color = 0x0,
            hoverColor = 0x0,
            clickedColor = 0x0,
            draggingColor = 0x0,
            isTint = false, -- Whether the modifier colors are aboslute or just a tinting of `color`
            autoCalcNav = true,
            focused = false,
            focusable = true,
        }
        -- These are pretty needed if you want to navigate.
        coreInstance:createHook(builder, "onFocus")
        coreInstance:createHook(builder, "onDrag")
        coreInstance:createHook(builder, "onHeld")
        coreInstance:createHook(builder, "onDoubleClicked")
        coreInstance:createHook(builder, "onClicked")
        coreInstance:createHook(builder, "onClicked")

        setmetatable(builder, {__index = self})
        builder.__index = self

        return builder
    end

    function MenuObjectBuilder:recalculateStyles()
        
    end

    -- As most things are in this framework, this position is relative to your parent
    function MenuObjectBuilder:setPosition(x,y,z)
        self:SetX(x):SetY(y):SetZ(z)
        return self
    end


    function MenuObjectBuilder:SetX(value)
        if value ~= nil then
            self.style.X = value
            self.computedStyle.X = computeNumericalUnit(self, value)
            self.gObject:SetX(self.computedStyle.X)
        end

        return self
    end
    
    function MenuObjectBuilder:SetY(value)
        if value ~= nil then
        self.style.Y = value
        self.computedStyle.Y = computeNumericalUnit(self, value, "y")
        self.gObject:SetY(self.computedStyle.Y)
        end

        return self
    end    
    function MenuObjectBuilder:SetZ(value)
        if value ~= nil then
        -- Fun fact. '-' is a operator. You can't just 'self.style.z-index'
        self.style["z-index"] = value
        self.computedStyle["z-index"] = computeNumericalUnit(self, value, "z-index")
        self.gObject:SetY(self.computedStyle["z-index"])
        end

        return self
    end
    
    function MenuObjectBuilder:setSize(w,h)
        if w ~= nil then
        self.style.width = w
        self.computedStyle.width = computeNumericalUnit(self, w, "width")
        end
        if h ~= nil then
        self.style.height = h
        self.computedStyle.height = computeNumericalUnit(self, h, "height")
        end

        self.gObject:setSize(self.computedStyle.width,self.computedStyle.height)
        return self
    end

    function MenuObjectBuilder:setColors(textColor, bgColor)
        self.gObject:setColors(textColor, bgColor)
        return self, true
    end
    function MenuObjectBuilder:setBackgroundColor(color)
        self.gObject:setBackgroundColor(color)
        return self
    end

    function MenuObjectBuilder:setTextColor(color)
        self.gObject:setTextColor(color)
        return self
    end

    function MenuObjectBuilder:show()
        
        return self
    end
    function MenuObjectBuilder:hide()
        
        return self
    end
    function MenuObjectBuilder:enable()
        
        return self
    end
    function MenuObjectBuilder:disable()
        
        return self
    end
    

    function MenuObjectBuilder:setParent(Object)

        return self
    end

    function MenuObjectBuilder:setChild(object)

        return self
    end

    MenuBuilder = {}
    
    function MenuBuilder:new(DOM)

    end

    function MenuBuilder:setParent(Object)

        return self
    end

    function MenuBuilder:setChild(object)

        return self
    end

    function MenuBuilder:SetSize(w, h)

        return self
    end

    function MenuBuilder:enable()
        
        return self
    end
    function MenuBuilder:disable()
        
        return self
    end

    ScrollBarBuilder = {}
    function ScrollBarBuilder:new()
        local builder = {
            backgroundObj = MenuObjectBuilder:new(),
            scrollHandle = MenuObjectBuilder:new(),
            scrollMin = 0,
            scrollMax = 0,  -- SET THESE LATER
            scrollCurrent = 0,
        }
        
        inheritFromInstance(self, builder, MenuObjectBuilder)
        
        -- This is obvious, but forgetting it would be disasterous.
        builder.backgroundObj:setParent(builder)
        builder.scrollHandle:setParent(builder.backgroundObj)

        return builder
    end

    function ScrollBarBuilder:computeHandleSize()
    end
    ScrollAreaBuilder = {}

    -- It's mostly just a basic menu object that scrolls
    function ScrollAreaBuilder:new()
        -- Derivation is based.
        local builder = {
            scrollbarObject = ScrollBarBuilder:new() -- TODO
        }

        inheritFromInstance({}, builder, MenuObjectBuilder)

        return builder
    end



    local function init(modules, core)
        -- tf was I doing here. Deps are fed in by name; If you require "Core" then just do modules["Core"]. It WILL exist as part of our dep management
        --[[for i,v in modules do
            
        end]]
        coreInstance = core
        BedrockGraphics = modules["Graphics"]
        BedrockInput = modules["Input"]
    end
    
    local function main(deltaTime)
        
    end

    local function cleanup()

    end

    BedrockUI = {
        type = "BedrockModule",
        moduleDefinition = {
            Init = init,
            Main = main,
            Cleanup = cleanup,
            moduleName = "UI",
            events = {
            },
            
            dependencies = {
                requirements = {
                    {moduleName = "Core", version = "*"},
                    {moduleName = "Graphics", version = "*"},
                    {moduleName = "Input", version = "*"}
                },
                optional = {

                },
                conflicts = {

                }
            },
            version = "0.0.0"
        },
        menuObjectBuilder = MenuObjectBuilder,
        menuBuilder = MenuBuilder,
        scrollAreaBuilder = ScrollAreaBuilder,
        scrollBarBuilder = ScrollBarBuilder
    }
    return BedrockUI