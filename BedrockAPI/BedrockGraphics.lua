--[[+----------------------------------------------------------+
    |                   GRAPHICS  MODULE                       |
    |                    +------------+                        |
    |        What this module handles: Graphics objects,       |
    |                      and some GFX                        |
    |                      Description:                        |
    | This module is designed to handle all graphics objects,  | 
    | effectively the HTML and CSS of Computercraft.           |
    | Except I'm better and don't need files.                  |
    | So just a graphics API I guess.                          |
    +----------------------------------------------------------+]]

    -- Side note. Bedrock Graphics isn't actually supposed to be html. It's not designed for interaction, but is more meant to only be for rendering. Some would maybe call that a scene graph.
    -- To explain: Bedrock graphics is only a higher level way to denote how to draw to the screen with retained mode rendering
    -- As a result many real HTML features fall outside of our scope. That includes any and all interactivity, and many effects that result.
    local BedrockGraphics = {}

    local bedrockCore = nil
        -- Basically what? huh? TELL ME
    -- Basically
    local monitors = {}

    local DOMs = {}

    local maxObjID = 0

    --- Searches a table for an object and returns it if it exists
    --- @param tbl table
    ---@param x any
    ---@return string | number | false
    ---@return any
    local function table_contains(tbl, x)
        for i, v in pairs(tbl) do
            if v == x then
                return i, v
            end
        end	
        return false, nil
    end

    
--[[+-------------------------+
    | FRAME RENDERING SECTION |
    +-------------------------+]]

     
    -- istfg if you overwrite this I will kill everyone. EVERYONE YOU HEAR ME???
    --- @param object gObject
    ---@param monitor genericMonitor
    local defaultMaterial = function (object, monitor)

        local preRender
        if object.computedValues.style.shaders ~= nil then
            preRender = object.computedValues.style.shaders.preRender
        end

        local cancelRender = false
        if preRender ~= nil then
            for i,v in pairs(preRender) do
                    if type(v) == "function" then
                        cancelRender = v(object, i,monitor)
                    end
            end
        end

        if not cancelRender then
            -- This works the same in practice as math.floor. Why this option?
            local epsilon = .001
            local origColor = term.getTextColor();
            local cursorPrevX,cursorPrevY = term.getCursorPos();
            local prevBGColor = term.getBackgroundColour();

            local objBGColor = object.DOM.getColor(object.computedValues.style.bgColor or -1, monitor)
            local objTextColor = object.DOM.getColor(object.computedValues.style.textColor or -1, monitor)
            local objStrokeColor = object.DOM.getColor(object.computedValues.style.strokeColor or -1, monitor)

            if not ( objBGColor == nil) and (objBGColor > -1) then
                paintutils.drawFilledBox(object.computedValues.x, object.computedValues.y, (object.computedValues.x + object.w - epsilon), (object.computedValues.y + object.h - epsilon), objBGColor)
            end
            
            if not ( object.style.strokeColor == nil) and (object.style.strokeColor > -1) then
                paintutils.drawBox(object.computedValues.x, object.computedValues.y, (object.computedValues.x + object.w - epsilon), (object.computedValues.y + object.h - epsilon), object.style.strokeColor)
                term.setBackgroundColor(prevBGColor)
            end
            if(objTextColor ~= nil and (objTextColor ~= -1)) then
                term.setTextColor(objTextColor)
                if not ( objBGColor == nil) and (objBGColor > -1) then
                    term.setBackgroundColor(objBGColor)
                end
                local tokens = {}
                for s in object.innerText:gmatch("[^\r\n]+") do
                    table.insert(tokens, s)
                end

                for num,v in ipairs(tokens) do
                    -- I want 0 indexing.
                    local offset = num - 1

                    if object.style.textAlign == nil or object.style.textAlign == "centered" then
                        term.setCursorPos((((object.w / 2) + object.computedValues.x) - (#v / 2)), ((object.h / 2) + object.computedValues.y + offset) - math.floor(#tokens / 2))
                    elseif object.style.textAlign == "topleft" then
                        term.setCursorPos(object.computedValues.x, (object.computedValues.y + offset))
                    end
                    
                    term.write(v)
                end
            end
            
            term.setTextColor(origColor)
            term.setBackgroundColor(prevBGColor)
            term.setCursorPos(cursorPrevX,cursorPrevY)
        end
           
        local postRender
        if object.computedValues.style.shaders ~= nil then
            postRender = object.computedValues.style.shaders.postRender
        end

        if preRender ~= nil then
            for i,v in pairs(preRender) do
                if type(v) == "function" then
                    v(object, i, monitor)
                end
            end
        end
    end
    
    local tempBuffer = {}
    local orderBuffer = {}
    -- They call me the 'I want O(1) please'
    orderBuffer.zCache = {}
    --- Renders every Object in a given DOM; NOT LABELED FOR INDIVIDUAL SALE (and by that I mean this isn't a global, how did you get here)
    --- @param object gObject
    ---@param monitor genericMonitor
    local function renderRecursive(object, monitor)
        
            if object.parent ~= nil and object.parent.computedValues ~= nil then
                object.computedValues = {
                    x = object.x + object.parent.computedValues.x - 1,
                    y = object.y + object.parent.computedValues.y - 1,
                    z = object.z + object.parent.computedValues.z,
                    style = {}
                }
                for style,value in pairs(object.style) do
                        object.computedValues.style[style] = value
                end

                for style,value in pairs(object.parent.computedValues.style) do
                    if object.computedValues.style[style] == nil then
                        object.computedValues.style[style] = value
                    end
                end
                
            elseif object.isDirty then
                object.computedValues = {
                    x = object.x,
                    y = object.y,
                    z = object.z,
                    style = {}
                }
                for style,value in pairs(object.style) do
                    object.computedValues.style[style] = value
                end 
                if object.parent ~= nil then
                    for style,value in pairs(object.parent.style) do
                        if object.computedValues.style[style] == nil then
                            object.computedValues.style[style] = value
                        end
                    end
                end
            end

        if object.colorDirty then
            object.colorDirty = false
            if object.DOM ~= nil then
                if object.style.textColor == nil then
                    object.DOM:registerColor(object.DOM.style.textColor, object)
                end
                if object.style.bgColor == nil then
                    object.DOM:registerColor(object.DOM.style.bgColor, object)
                end
                if object.style.strokeColor == nil then
                    object.DOM:registerColor(object.DOM.style.strokeColor, object)
                end
            end
            object.DOM:allocateColors(monitor)
        end

        if not object.setupDone then
            object.setupDone = true
            object.setup()
        end

        if object.DOM ~= nil then
                if tempBuffer[object.computedValues.z] == nil and orderBuffer.zCache[object.computedValues.z] ~= true then
                    tempBuffer[object.computedValues.z] = {}
                    if #orderBuffer == 0 then
                        table.insert(orderBuffer, object.computedValues.z)
                    else
                        if object.computedValues.z ~= nil then
                            local low = 1
                            local high = #orderBuffer
                            local insertPos = #orderBuffer + 1
                            while low <= high do
                                local mid = math.floor((low + high) / 2)
                                if orderBuffer[mid] < object.computedValues.z then
                                    low = mid + 1
                                elseif orderBuffer[mid] > object.computedValues.z then
                                    insertPos = mid
                                    high = mid - 1
                                else
                                    insertPos = mid
                                    break
                                end
                            end
                            if orderBuffer[insertPos] ~= object.computedValues.z then
                                table.insert(orderBuffer, insertPos, object.computedValues.z)
                                orderBuffer.zCache[object.computedValues.z] = insertPos
                            end
                        end
                    end
                end

                table.insert(tempBuffer[object.computedValues.z], object)
        end
        if object.children ~= nil then
            for i,v in ipairs(object.children) do
                if v.enabled then
                    -- If the parent is dirty then so are the children.
                    if object.isDirty then
                        -- I just didn't want to cascade outside the render compute cascade.
                        v.isDirty = true
                    end
                    renderRecursive(v, monitor)
                end
            end
        end
        object.isDirty = false -- We do it at the end for lazy cascading.
    end 

    --- Takes an object and flags it's monitors for a redraw
    --- @param object gObject
    local function flagForRedraw(object)
        object.isDirty = true
        -- Get the DOM
        local DOM = object.DOM
        if DOM ~= nil then
            -- And if there are monitors...
            if DOM.trackedMonitors ~= nil then
            -- Go through each and mark them dirty
                for i,v in pairs(DOM.trackedMonitors) do
                    monitors[v]["object"].redraw = true
                end
            end
            return true
        end
        return false
    end

    --- Renders a frame on all monitors; What do you want me to put here.
    local function renderFrame()
        for i,v in pairs(monitors) do
                tempBuffer = {}
                local monitor = v["object"]
             -- If the monitors dirty..
            if monitor.redraw then
                BedrockGraphics.moduleDefinition.hooks.OnRenderFrameStart(monitor.base.name, v)
                -- set it as clean
                monitor.redraw = false
                -- Get the term to go back to after we're done here
                local currentTerm = term.current();

                -- Check the terms size
                monitor.onResize("nil", monitor, monitor.base.name)

                -- Redirect to the buffer that IS NOT visible. 
                if monitor.buffers[1].isVisible() then
                    term.redirect(monitor.buffers[2])
                else
                    term.redirect(monitor.buffers[1])
                end
                
                -- Go through every DOM in this monitor, and render it's contents
                -- We don't sort the DOMS, and it's bad practice to have multiple DOMs bound to a monitor, but you can if you want, I guess
                for i2,v2 in ipairs(v) do
                    if v2.colorDirty then
                        v2.colorDirty = false
                        v2:allocateColors(monitor)
                    end
                    -- DOM layer
                    tempBuffer = {}
                    
                    v2.hooks.onFrameStart()
                    renderRecursive(v2, monitor)
                    local theRemoved = {}
                        for ia,vb in ipairs(orderBuffer) do
                            if tempBuffer[vb] ~= nil then
                                for _,vd in pairs(tempBuffer[vb]) do
                                    vd:Render(monitor)
                                end
                            else
                                table.insert(theRemoved, ia)
                            end
                            tempBuffer[vb] = {} -- Clear the frame but not the metadata
                        end
                        local offset = 0
                        for _,v3 in ipairs(theRemoved) do
                            orderBuffer.zCache[orderBuffer[v3 - offset]] = nil
                            table.remove(orderBuffer, v3 - offset)
                            offset = offset + 1
                        end
                    -- Swap visibility so that we can see our drawing. We do this after rendering to reduce
                    monitor.buffers[1].setVisible(not monitor.buffers[1].isVisible())
                    monitor.buffers[2].setVisible(not monitor.buffers[2].isVisible())
                    v2.hooks.onFrameEnd()
                end

                -- If it's a printer, end the page to print our frames output. 
                if monitor.base.type == "printer" then
                        monitor.generic.endPage()
                end
                -- redirect to the previous 'term'
                if monitor.base.type ~= "term" then
                    term.redirect(currentTerm)
                end
                
                BedrockGraphics.moduleDefinition.hooks.OnRenderFrameEnd(monitor.base.name, v)
            end
        end
        
    end

    local function flagZDirty(object)
        if object.DOM ~= nil then
            object.DOM.zDirty = true
        end
        object.zDirty = true
    end
    
--[[+-------------------------+
    | GRAPHICS OBJECT SECTION |
    +-------------------------+]]

    -- Trying to avoid reallocating colors where possible.
    local function markColorDirty(object, color)
        local found = true
        for i,v in pairs(object.DOM.trackedMonitors) do
            local color = monitors[v]["object"].colors[color]
            if color == nil or color.inPallete or not (object.w * object.h > 1/4 * color.size)then
                found = false
                break
            end
        end

        if not found then
            object.colorDirty = true
            object.DOM.colorDirty = true
        end 
    end

    --- A builder pattern to create any gObject
    local ObjectBase = {}

    --- Enables the gObject for display; Could also be called show
    --- @return self
    function ObjectBase:enable()
        if not self.enabled then
            self.enabled = true
            if self.DOM ~= nil then
                self.DOM:registerColor(self.style.bgColor, self)
                self.DOM:registerColor(self.style.textColor, self)
            end
            
            flagForRedraw(self)

            self.hooks.onEnable()
            self.hooks.onVisibilityChange(self.enabled)
        end

        return self
    end

    --- Disables the gObject, and prevents it's display; Could also be called hide
    --- @return self
    function ObjectBase:disable()
        if self.enabled then
            self.enabled = false
            if self.DOM ~= nil then
                self.DOM:relinquishColor(self.style.bgColor, nil, self)
                self.DOM:relinquishColor(self.style.textColor, nil, self)
            end

            flagForRedraw(self)

            self.hooks.onDisable()
            self.hooks.onVisibilityChange(self.enabled)
        end
        return self
    end

    local function recursiveReDOM(object, DOM)
            object.DOM = DOM
            for i,v in ipairs(object.children) do
                -- Given that reDOMing is recursive like this. If the child has a DOM so does it's children.
                if v.DOM ~= DOM then
                    recursiveReDOM(v, DOM)
                end
            end
    end

    --- Reparents an object.  
    --- I'd recomend rarely doing this if you can. It's just kind of costly.
    --- It is more than quick enough for almost every application, but don't abuse leeway.
    --- @param object gObject
    --- @return self
    function ObjectBase:setParent(object)
        if type(object) == "table" and (object.type == "gObject" or object.type == "DOM") then


            self.hooks.onSetParent(self, object)
            if self.DOM ~= nil and object.DOM ~= nil then
                self.DOM:relinquishColor(self.style.textColor, nil, self)
                self.DOM:relinquishColor(self.style.bgColor, nil, self)
            end
            if self.parent ~= nil then
                table.remove(table_contains(self.parent.children, self))
            end
            self.parent = object
            self.DOM = object.DOM
            if self.DOM ~= nil then
                self.DOM.hooks.onAddChild(self.DOM, self)
                self.DOM:registerColor(self.style.textColor, self)
                self.DOM:registerColor(self.style.bgColor, self)
            end
            table.insert(self.parent.children, self)
            if self.DOM ~= nil then
                recursiveReDOM(self,self.DOM)
            end
            self.parent.zDirty = true
            self.zDirty = true
            flagZDirty(self.parent)

            flagForRedraw(self)
        end
        return self
    end

    --- Adds a child to our gObject  
    --- Watch out. This uses setParent so it's more costly than it.
    --- @param object gObject                                                                                                                                                                                                                                                                                                                             `ject
    --- @return self
    function ObjectBase:addChild(object)
        if type(object) == "table" and (object.type == "gObject" or object.type == "DOM") then
            self.hooks.onAddChild(self, object)
           object:setParent(self)
        end
        flagForRedraw(self)
        return self
    end

    --

    --- Instantiates a new gObject 
    --- @alias gObject table
    --- @return gObject
    function ObjectBase:new()

        local builder = {
            type = "gObject",
            monitors = {},
            isBuilt = false,
            x = 1,
            y = 1,
            z = 1,
            w = 1,
            h = 1,
            enabled = true,
            parent = nil,
            children = {},
            innerText = "",
            style = {
                textColor = nil,
                bgColor = nil,
                strokeColor = nil,
            },
            colorDirty = true,
            isDirty = true,
            setup = function ()
                
            end,
            setupDone = false,
            DOM = nil,
            Render = defaultMaterial -- Materials are the functions called to render an object. No I will not be normal
        }
        bedrockCore:createHook(self, "onEnable"):createHook(self, "onDisable"):createHook(self, "onVisibilityChange", "boolean")
        
        -- The first table is the object that has experience the change 
        -- The string is the changed styles name, and the any is it's new value
        bedrockCore:createHook(self, "onScaleChange", "table"):createHook(self, "onWidthChange", "table"):createHook(self, "onHeightChange", "table")
        bedrockCore:createHook(self, "onPositionChange", "table"):createHook(self, "onXChange", "table"):createHook(self, "onYChange", "table"):createHook(self, "onZChange", "table")
        bedrockCore:createHook(self, "onTextChange", "table")
        bedrockCore:createHook(self, "onStyleChange", "table", "string", "any")

        bedrockCore:createHook(self, "onAddChild", "table", "table")
        bedrockCore:createHook(self, "onSetParent", "table", "table")
        setmetatable(builder, {__index = self, __name = "gObject"})
        builder.__index = self

        return builder
    end

    function ObjectBase:setStyle(style, value)
        -- Basically a switch statement mom I swear.
        local preDefStylesLUT = {
            textColor = function ()
                return self:setTextColor(value)
            end,
            bgColor = function ()
                return self:setBackgroundColor(value)
            end,
            strokeColor = function ()
                error("NYI") -- Hiiiii.
            end,
            x = function ()
                self:setX(value)
            end,
            y = function ()
                self:setY(value)
            end,
            z = function ()
                self:setZ(value)
            end,
            width = function ()
                self:setWidth(value)
            end,
            height = function ()
                self:setHeight(value)
            end,
            visible = function ()
                if value == true or value == "true" then
                    self:enable()
                else
                    self:disable()
                end
            end
        }

        self.style[style] = value

        if preDefStylesLUT[style] ~= nil then
            preDefStylesLUT[style]()
        end

        flagForRedraw(self)

        self.hooks.onStyleChange(self, style, value)
        return self, true
    end

    --- A way to set all colors of an object
    --- @alias color 
    --- | "integer" # Integer representing hexadecimal color 
    --- @param textColor color
    --- @param bgColor color
    --- @return self
    function ObjectBase:setColors(textColor, bgColor)
        self:setBackgroundColor(bgColor)
        self:setTextColor(textColor)
        return self
    end

    --- Sets the text color of an object
    --- @param textColor color
    --- @return self
    function ObjectBase:setTextColor(textColor)
        assert(type(textColor) == "number", "Given color isn't the right type! ( Expected number. Got" .. type(textColor) .. ")")
        if self.DOM ~= nil and self.enabled then 
        self.DOM:relinquishColor(self.style.textColor, nil, self)
        end
        self.style.textColor = textColor
        self.hooks.onStyleChange(self, "textColor", textColor)
        if self.DOM ~= nil and self.enabled then
        markColorDirty(self, textColor)
        self.DOM:registerColor(self.style.textColor, self)
        end
        flagForRedraw(self)
        return self
    end

    --- Sets the bg color of an object
    --- @param bgColor color
    --- @return self
    function ObjectBase:setBackgroundColor(bgColor)
        assert(type(bgColor) == "number", "Given color isn't the right type! ( Expected number. Got" .. type(bgColor) .. ")")

        if self.DOM ~= nil and self.enabled then 
            self.DOM:relinquishColor(self.style.bgColor, nil, self)
        end
        self.style.bgColor = bgColor
        self.hooks.onStyleChange(self, "bgColor", bgColor)
        if self.DOM ~= nil and self.enabled then
            markColorDirty(self, bgColor)
            self.DOM:registerColor(self.style.bgColor, self)
        end


        flagForRedraw(self)
        return self
    end
    
    --- Sets the size of an object
    --- @param width integer
    --- @param height integer
    --- @return self
    function ObjectBase:setSize(width, height)
        self:setWidth(width)
        self:setHeight(height)

        return self
    end

    --- Sets the width of an object
    --- @param width integer
    --- @return self
    function ObjectBase:setWidth(width)
        assert(type(width) == "number", "Given width isn't the right type! ( Expected number. Got" .. type(width) .. ")")
        self.w = math.ceil(width)
        self.hooks.onScaleChange(self)
        self.hooks.onWidthChange(self)
        flagForRedraw(self)
        return self
    end 

    --- Sets the height of an object
    --- @param height integer
    --- @return self
    function ObjectBase:setHeight(height)
        assert(type(height) == "number", "Given height isn't the right type! ( Expected number. Got" .. type(height) .. ")")
        self.h = math.ceil(height)
        self.hooks.onScaleChange(self)
        self.hooks.onHeightChange(self)
        flagForRedraw(self)
        return self
    end 
    
    --- Sets the position of an object
    --- @param X integer
    --- @param Y integer
    --- @param Z integer
    --- @return self
    function ObjectBase:setPosition(X, Y, Z)
        self:setX(X or self.x)
        self:setY(Y or self.y)
        self:setZ(Z or self.z)
        return self
    end

    --- Sets the X position of an object
    --- @param X integer
    --- @return self
    function ObjectBase:setX(X)
        assert(type(X) == "number", "Given X isn't the right type! ( Expected number. Got" .. type(X) .. ")")
        self.x = math.ceil(X)
        self.hooks.onPositionChange(self)
        self.hooks.onXChange(self)
        flagForRedraw(self)
        return self
    end 

    --- Sets the Y position of an object
    --- @param Y integer
    --- @return self
    function ObjectBase:setY(Y)
        assert(type(Y) == "number", "Given Y isn't the right type! ( Expected number. Got" .. type(Y) .. ")")
        self.y = math.ceil(Y)
        self.hooks.onPositionChange(self)
        self.hooks.onYChange(self)
        flagForRedraw(self)
        return self
    end 

    --- Sets the Z position of an object
    --- @param Z integer
    --- @return self
    function ObjectBase:setZ(Z)
        assert(type(Z) == "number", "Given Z isn't the right type! ( Expected number. Got" .. type(Z) .. ")")
        self.z = math.ceil(Z)
        self.hooks.onPositionChange(self)
        self.hooks.onZChange(self)
        flagZDirty(self)
        flagForRedraw(self)
        return self
    end 

    --- Sets the innerText style of an object
    --- @param text string
    --- @return self
    function ObjectBase:setText(text)
        --assert(type(text) == "string", "Given text isn't the right type! ( Expected string. Got" .. type(text) .. ")")
        self.innerText = tostring(text)
        self.hooks.onTextChange(self)
        flagForRedraw(self)
        return self
    end

    -- God I love calling what is effectively a shader a material. Shut up I assume my users will be children playing minecraft trying to make toys.
        -- Isn't it just a material shader? 
        
    --- Sets the material of an object
    --- @param material function
    --- @return self
    function ObjectBase:setMaterial(material)
        assert(type(material) == "function", "Given material isn't the right type! ( Expected function. Got" .. type(material) .. ")")
            self.render = material
        flagForRedraw(self)
        return self
    end

    --- Sets the setup function of an object  
    ---   
    --- A setup function runs once before the first render to setup state. Useful to setup custom color registration logic to make sure your colors don't get overridden  
    ---   
    --- running this function marks an object as not set up as to make it run. You can exploit this if you put no setup function to not modify the last function, but still reset the flag
    --- @param func function
    --- @return self
    function ObjectBase:addSetupFunction(func)
        self.setup = func or self.setup
        self.setupDone = false
        flagForRedraw(self)
        return self
    end

    -- Padding is text only. We can't really control how other gObjects choose to render, but we do hope they cooperate
    --- Sets the padding of a gObject
    --- @param top integer
    ---@param bottom integer
    ---@param left integer
    ---@param right integer
    ---@return self
    function ObjectBase:setPadding(top, bottom, left, right)

        flagForRedraw(self)
        return self
    end

    --- Sets the padding for the top side of a gObject
    --- @param padding integer
    --- @return self
    function ObjectBase:setTopPadding(padding)
        self.style.paddingtop = padding
        flagForRedraw(self)
        return self
    end

    --- Sets the padding for the bottom side of a gObject
    --- @param padding integer
    --- @return self
    function ObjectBase:setBottomPadding(padding)
        self.style.paddingbottom = padding
        flagForRedraw(self)
        return self
    end
    
    --- Sets the padding for the left side of a gObject
    --- @param padding integer
    --- @return self
    function ObjectBase:setLeftPadding(padding)
        self.style.paddingleft = padding
        flagForRedraw(self)
        return self
    end
    
    --- Sets the padding for the right side of a gObject
    --- @param padding integer
    --- @return self
    function ObjectBase:setRightPadding(padding)
        self.style.paddingright = padding
        flagForRedraw(self)
        return self
    end


    local MaskObject = {}


    -- It is no different an inferface but like... you can't render outside of it.
    function MaskObject.new()
        local builder = {}

        setmetatable(builder, {__index = ObjectBase})
        builder = ObjectBase:new()

        return builder
    end
--[[+---------------+
    |  DOM SECTION  |
    +---------------+]]


    local DomBuilder = {}
    function DomBuilder.new()
        local builder = {
            type = "DOM",
            x = 1,
            y = 1,
            z = 0,
            w = 0,
            h = 0,
            children = {},
            innerText = "",
            style = {
                textColor = colors.packRGB(term.nativePaletteColour(colors.white)), -- Have a fallback if no one ever declares a color
                bgColor = colors.packRGB(term.nativePaletteColour(colors.black))
            },
            trackedMonitors = {},
            colors = {},
            colorsInUse = {},
            colorDirty = true,
            setupDone = true, -- To stop it from trying to setup. You can't setup a dom.
            Render = function () end, -- Eeh hee hee. Nobody tell anyone that we actually render DOMS, too!
            hooks = {},
        }
        -- Create a bunch of needed hooks
        --- onPalleteAllocate & onPreallocatePallete hookt
        --- NOTE: onPreallocatePallete will have the values of the previous frame usually. At least as it's currently implemented
        --- @params monitorPalette table
        --- @params palettePreAverage table  # omitted in Preallocate
        --- @params allRegisteredColors table
        --- @params unusedColors table #Unused colors occur if there are more than 16 colors as per CC's limits.


        bedrockCore:createHook(builder, "onFrameStart"):createHook(builder, "onFrameEnd"):createHook(builder, "onPreallocatePallete", "table", "table", "table"):createHook(builder, "onAllocatePallete", "table", "table", "table", "table")

        bedrockCore:createHook(builder, "onAddChild", "table", "table"):createHook(builder, "onRemoveChild","table", "table")

        setmetatable(builder, {__index = DomBuilder, __name = "DOM"})
        table.insert(DOMs, builder)
        
        builder.DOM = builder

        return builder
    end
    function DomBuilder:clear()

        for i,v in pairs(self.trackedMonitors) do
            for i2, col in pairs(self.colors) do
            DomBuilder:relinquishColor(col.value, monitors[v]["object"], col)
            end
        end
        
        self.colors = {}
        self.colorsInUse = {}

        self.DOM:registerColor(self.style.bgColor, self)
        self.DOM:registerColor(self.style.textColor, self)

        for i,v in ipairs(self.children) do
            self.hooks.onRemoveChild(self, v)
        end
        self.children = {}
        return self
    end

    function DomBuilder:addMonitor(monitor)
        if monitors[monitor.base.name] == nil then
            monitors[monitor.base.name] = {}
        end
        if monitors[monitor.base.name]["object"] == nil then
            monitors[monitor.base.name]["object"] = monitor
        end
        table.insert(self.trackedMonitors, monitor.base.name)
        table.insert(monitors[monitor.base.name], self)
        monitor.redraw = true
        flagForRedraw(self)
        return self

    end

    -- Handles monitor resizing. It's implementation also works for term redirects
    local function handleMonitorResize(monitor)
        if monitors[monitor] ~= nil then
                monitors[monitor]["object"].redraw = true
        end
    end

    -- color gets it's own section because it's complicated and scary.

--[[+-------------------+
    |   COLOR SECTION   |
    +------------------+]]

    -- Used only by the frame renderer.
    --- Gets a color from a provided hex code from a given monitor
    --- NOT A BUILDER! Just an instance method. This won't return itself
    function DomBuilder.getColor(code, monitor)
        if code == nil or (type(code) == "number" and code < 0) then
            return code
        end

        if type(code) == "number" then
            local renderableSubset = monitor.colorsInUse

            -- Early simple lookup for if the color is already in the palette.
            for i,v in ipairs(renderableSubset) do
                if v.preComputedValue == code or v.value == code then
                    return 2 ^ (i - 1), code, i
                end
                
            end
            
            -- For colors that don't exist or failed to make it in. Find their closest match.
            table.sort(renderableSubset, function (a, b)
                if a == nil or b == nil then
                    -- This isn't possible. It's a logic bomb. Don't worry JIT will make sure it will happen
                    error("Illegal state! Hole found in the palette!")
                end
                -- Sort the value with the least difference 
                local Adifference = 0
                local Bdifference = 0
                local codeRGB = {colors.unpackRGB(code)}
                for i,v in ipairs(table.pack(colors.unpackRGB(a.value))) do
                    Adifference = Adifference + math.abs((v) - (codeRGB[i]))
                end
                for i,v in ipairs(table.pack(colors.unpackRGB(b.value))) do
                    Bdifference = Bdifference + math.abs((v) - (codeRGB[i]))
                end
                return Adifference < Bdifference
            end)
            for i,v in pairs(monitor.colorsInUse) do
                -- Return the closest value that is contained.
                if v == renderableSubset[1] then
                    return 2 ^ (i - 1), v, i
                end
            end

            -- If you got here, then you are firmly in traceback territory. Sorry! Well not traceback, but I mean, close.
            for i,v in pairs(renderableSubset) do
                print(i,v)
            end
            read()

            -- No color being found means there were no colors to search. We shouldn't be able to get here, hence the error.
            error("No color found for color: " .. code .. "(" .. #renderableSubset .. " Colors in the palette)")
            return nil, "No color found for color: " .. code
        else
            error("Incorrect type!")
        end

    end

    --- Registers a literal hexadecimal graphics color to be used, or if it exists already then add to the instances using it
    --- @param colorValue color
    ---@param colorObject gObject
    --- @return table 
    function DomBuilder:registerColor(colorValue, colorObject)
        if colorValue == nil or colorValue < 0 then
            return colorValue
        end
        local theColor = nil
        for i,a in ipairs(self.trackedMonitors) do
            local v = monitors[a]["object"]
            
            theColor = v.colors[colorValue]

            if theColor == nil then
            -- can't use color here because that's an important global
            theColor = {
                value = colorValue, -- Hex Value
                instances = 1,
                size = colorObject.w * colorObject.h,
                inPallete = false,
            }
            else
                theColor.instances = theColor.instances + 1
                theColor.size = theColor.size + (colorObject.h * colorObject.w)
            end
            v.colors[colorValue] = theColor
        end
        
            self.colors[colorValue] = theColor
        return self
    end

    --- Relinquishes a color from the palette
    --- @param color color
    ---@param instances integer # The amount of instances to relinquish
    function DomBuilder:relinquishColor(color, monitor, colorObj)
        if colorObj.type == "DOM" or colorObj.type == "gObject" then
            colorObj = {
                instances = 1,
                size = colorObj.w * colorObj.h
            }
        end
        -- Is this a result of technical debt? ...Yes :(
            -- Well okay not that much tech debt. I just added the monitor param, and the instances param. 
        local _monitors = monitor ~= nil and {monitor} or {}
        if monitor == nil then
            for i,a in ipairs(self.trackedMonitors) do
                table.insert(_monitors, monitors[a]["object"])
            end
        end
        if color == nil or color < 0 then
            return color
        end
        if type(color) =="table" then
            for i,v in ipairs(_monitors) do
                for key, value in pairs(v.colors) do
                    if value == color then
                        value.instances = value.instances - colorObj.instances
                        value.size = value.size - colorObj.size
                        
                        if(value.instances <= 0) then
                            v.colors[key] = nil
                        end
                        if v.colors ~= nil and v.colors[color] ~= nil then
                            self.colors[color] = v.colors[color]
                        else 
                            if self.colors ~= nil then
                                self.colors[color] = nil
                            else 
                                self.colors = {}
                            end
                        end
                        v.colors = v.colors or {}
                        return true, key
                    end
                end
            end
        elseif type(color) == "number" or type(color) == "string" then
            for i,v in ipairs(_monitors) do
                if v.colors ~= nil and v.colors[color] ~= nil then
                v.colors[color].instances = v.colors[color].instances - colorObj.instances
                if(v.colors[color].instances <= 0) then
                    v.colors[color] = nil
                end
                end

                if v.colors ~= nil and v.colors[color] ~= nil then
                    self.colors[color] = v.colors[color]
                else 
                    if self.colors ~= nil then
                        self.colors[color] = nil
                    else 
                        self.colors = {}
                    end
                end
                v.colors = v.colors or {}
            end
            return true
        end
        return false
    end

    --- Allocates every color in the DOM to the palette.  
    --- I exposed it, but trust me you don't want to use this on your own.  
    --- Oh and it'll eat resources like nobodies business.
    --- @param monitor genericMonitor
    --- @return self
    function DomBuilder:allocateColors(monitor)
            -- Jit forcing me to add explicit checks yet again; hooks can't not exist.
            if self.hooks ~= nil then
            self.hooks.onPreallocatePallete(monitor.colorsInUse, monitor.colors, monitor.unrenderedSubset or {})
            end
            local renderableSubset = {}

            if monitor.colors == nil then
                monitor.colors = {}
            end
            
            for i,v in pairs(monitor.colors) do
                if v ~= nil then 
                table.insert(renderableSubset,v)
                end
            end
            
            table.sort(renderableSubset, function (a, b)
                -- If the instances are equal, then fallback
                if a.instances + a.size ~= b.instances + b.size then
                -- Sort the value with the most instances 
                return a.instances + a.size >= b.instances + b.size
                else
                    return a.value > b.value
                end
            end) 

            for i,v in ipairs(renderableSubset) do
                v.inPallete = i <= 16
            end

            local unrenderedSubset = #renderableSubset > 16 and table.pack(table.unpack(renderableSubset, 16, #renderableSubset)) or {}
            monitor.unrenderedSubset = unrenderedSubset
            -- Get the first 16 items in the rendereable subset
            renderableSubset = table.pack(table.unpack(renderableSubset, 1, 16))
            monitor.colorsInUse = {}
            for i,v in ipairs(renderableSubset) do
                monitor.colorsInUse[i] = v
            end

            for i,v in ipairs(unrenderedSubset) do
                -- Gets the color closest to v. Side note. This is mostly used for rendering and quantization. I love cheating and reusing code
                local _, _, closestI = self.getColor(v.value, monitor)
                local rgb1 = {colors.unpackRGB(renderableSubset[closestI].value)}
                local rgb2 = {colors.unpackRGB(v.value)}
                for i, v2 in ipairs(rgb1) do
                    rgb1[i] = rgb1[i] + (rgb2[i] * (v.instances * v.size / (renderableSubset[closestI].instances * renderableSubset[closestI].size)))
                end
                renderableSubset[closestI].rgb = rgb1
                renderableSubset[closestI].avgInstances = renderableSubset[closestI].avgInstances ~= nil and renderableSubset[closestI].avgInstances + 1 or 1
            end
            

            monitor.colorsInUse = {}
            for i,v in ipairs(renderableSubset) do
                if v.avgInstances ~= nil then
                    local rgb3 = v.rgb
                    for i2, v2 in ipairs(rgb3) do
                        rgb3[i2] = rgb3[i2] / v.avgInstances
                    end
                    v.preComputedValue = v.value
                    v.value = colors.packRGB(table.unpack(rgb3, 1, 3))
                end
                monitor.colorsInUse[i] = v
                local colorIdx = 2^(i-1)
                monitor.functions.setPaletteColour(colorIdx, v.value)
                monitor.buffers[1].setPaletteColour(colorIdx, v.value)
                monitor.buffers[2].setPaletteColour(colorIdx, v.value)
            end
            if self.hooks then
                self.hooks.onAllocatePallete(monitor.colorsInUse, renderableSubset, monitor.colors, unrenderedSubset or {})
            end
        return self
    end
    --- Clears the DOM and attempts to relinquish it's resources
    --- @return self

    
--[[+--------------------+
----| LIFE CYCLE SECTION |
-------------------------+]]
---
    local function init(modules, core)
        -- monitors being resized means instant redraw flag. Mostly because it's scary (also they clear themselves on resize)
        bedrockCore = core
        bedrockCore:registerEvent("term_resize", function() handleMonitorResize("term") end)
        bedrockCore:registerEvent("monitor_resize", function(ev, display) handleMonitorResize(display) end)
        -- Put hooks in your module definition as best practice. Just makes it easier to find, since it's the most likely to be shared
        -- Conversely. To hide some hooks. Don't.
        --- OnRenderFrameStart & OnRenderFrameEnd
        --- @param monitorName string # The name of the monitor we're rendering to 
        --- @param DOMsAttached table # The DOMs attached to the monitor


        core:createHook(BedrockGraphics.moduleDefinition, "OnRenderFrameStart", "string", "table"):createHook(BedrockGraphics.moduleDefinition, "OnRenderFrameEnd", "string", "table")
        -- ? 
        local idx = 1
    end
    
    local function main(deltaTime)
        renderFrame()
    end

    local function cleanup()
        local uniqueColors = 16
        local monitor
        -- Fun fact monitors can be a form of shared state. Don't clear their colors, but instead relinquish your colors.
        for i,v in pairs(monitors) do
                -- Colors themselves are keyed by their values from what I remember.
                -- Don't name indexes like this. I will hate myself soon.
                for i7trillion, col in pairs(v["object"].colors) do
                    -- This shouldn't be possible to be nil. I'm going to regret saying that
                    v[1]:relinquishColor(col.value, nil, col)
                end
        end

        for i,v in pairs(monitors) do
            local v3 = v["object"]
            if v3 ~= nil then
                if v3.base.name == i then
                    monitor = v3
                    monitor.functions.clear()
                    break
                end
            end
        end
        -- Make sure a monitor was found rather than assuming it was. 
        if monitor ~= nil then
            for i2 = 1, uniqueColors, 1 do
                local idx = 2^(i2-1)
                monitor.functions.setPaletteColour(idx, colors.packRGB(term.nativePaletteColor(idx)))
            end

            for i,v in pairs(monitor.buffers) do
                v.clear()
                v.setVisible(false)
                monitor.buffers = nil
            end
            term.setCursorPos(1,1)
        end
    end

--[[+------------------+
----| API  DEFINITIONS |
-----------------------+]]

    BedrockGraphics = {
        type = "BedrockModule",
        moduleDefinition = {
            Init = init,
            Main = main,
            Cleanup = cleanup,
            moduleName = "Graphics",
            events = {
            },
            dependencies = {
                requirements = {
                    {moduleName = "Core", version = "*"},
                    {moduleName = "Input", version = "*"}
                },
                optional = {

                },
                conflicts = {

                }
            },
            version = "0.3.1", -- Huh actually semVering for once. God
            priority = 1,
        },
        domBuilder = DomBuilder,
        objectBase = ObjectBase,
        RenderFrame = renderFrame,
        maskObject = MaskObject,
    }
    return BedrockGraphics

    -- Life is a highway. I'm gonna ride it all nigh- until I crash and burn because my gearshifter doesn't center normally, or a spider. Your choice.