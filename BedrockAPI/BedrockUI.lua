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

-- Don't set them to nil (despite that they are) because I don't want to hear my IDE complain I need nil checks (I don't)
local BedrockGraphics = {}
local BedrockInput = {}
local coreInstance = {}
local BedrockUI = {}

-- Do I know how to quadtree. No not really. But quite a bit actually.
local QuadTree = {}

function QuadTree:subdivide()
    local w = self.width / 2
    local h = self.height / 2

    local remainingDepth = self.maxDepth - 1
    if self.nodes == nil then
        -- I hate my life.
        self.nodes = {}
        self.nodes.tl = QuadTree.new(self.x, self.y, w, h, remainingDepth, self.maxObjects)
        self.nodes.tr = QuadTree.new(self.x + w, self.y, w, h, remainingDepth, self.maxObjects)
        self.nodes.bl = QuadTree.new(self.x, self.y + h, w, h, remainingDepth, self.maxObjects)
        self.nodes.br = QuadTree.new(self.x + w, self.y + h, w, h, remainingDepth, self.maxObjects)
    end
    self.isSplit = true

    return self
end

function QuadTree:clear()
    self.nodes = {}
    self.isSplit = false
    return self
end

-- Do I know what I'm doing. No. To be fair this doesn't require knowing much of anything
function QuadTree:find(x,y)
        if x <= self.centerX and y <= self.centerY then
            return "tl";
        elseif x <= self.centerX and y > self.centerY then
            return "bl";
        elseif x > self.centerX and y <= self.centerY then
            return "tr";
        elseif x > self.centerX and y > self.centerY then
            return "br";
        end
end

local fh = fs.open("_temp2", "w+")

-- Grabs every object at a given x and y
function QuadTree:grab(x,y)
    -- I choose not to explain. Too tired
    if self.isSplit then
        local a, obj = self.nodes[self:find(x, y)]:grab(x,y)

        return self, obj
    end
    
    return self, self.objects
end

function QuadTree:resize(x,y,w,h)
    self.x = x
    self.y = y
    self.width = w
    self.height = h

    w = w / 2
    h = h / 2

    self.centerX = x + w
    self.centerY = y + h

    if self.nodes ~= nil then
        self.nodes.tl:resize(self.x,self.y, w, h)
        self.nodes.tr:resize(self.x + w,self.y, w, h)
        self.nodes.bl:resize(self.x,self.y + h, w, h)
        self.nodes.br:resize(self.x + w, self.y + h, w, h)
    end

    return self
end

function QuadTree:insert(object)
    if object.nodeKeys == nil then
        object.nodeKeys = {}
    end
    if object.nodes == nil then
        object.nodes = {}
    end
    -- I love short circuit logic. 
    if self.isSplit then
            if object.x < self.centerX then
                if object.y < self.centerY then
                    self.nodes.tl:insert(object,x,y)
                end
                if object.y + object.h > self.centerY then
                    self.nodes.bl:insert(object,x,y)
                end
            end
            if object.x + object.w > self.centerX then
                if object.y < self.centerY then
                    self.nodes.tr:insert(object,x,y)
                end
                if object.y + object.h > self.centerY then
                    self.nodes.br:insert(object,x,y)
                end
            end
        return self
    end

    self.nodeID = self.nodeID ~= nil and self.nodeID + 1 or 1
    self.numObjects = self.numObjects + 1
    self.objects[self.nodeID] = object

    if self.numObjects > self.maxObjects and self.maxDepth > 0 then
        self:subdivide()

        -- figure out how to do rectangles. god
        for i,v in pairs(self.objects) do

            object.nodes[i] = nil
            object.nodeKeys[i] = nil

            if v.x < self.centerX then
                if v.y < self.centerY then
                    self.nodes.tl:insert(v)
                end
                if v.y + v.h > self.centerY then
                    self.nodes.bl:insert(v)
                end
            end
            if v.x + v.w > self.centerX then
                if v.y < self.centerY then
                    self.nodes.tr:insert(v)
                end
                if v.y + v.h > self.centerY then
                    self.nodes.br:insert(v)
                end
            end
        end

        self.objects = {}
        self.numObjects = 0
        self.nodeID = 0
    else
        object.nodeAmnt = object.nodeAmnt ~= nil and object.nodeAmnt + 1 or 1
        object.nodeKeys[object.nodeAmnt] = self.nodeID
        object.nodes[object.nodeAmnt] = self
    end
    return self
end

function QuadTree:remove(Object)
    for i,v in pairs(Object.nodeKeys) do
        Object.nodes[i].numObjects = Object.nodes[i].numObjects - 1
        Object.nodes[i].objects[v] = nil
    end

    Object.nodeKeys = nil
    Object.nodes = nil

    return self
end

function QuadTree:refreshNode(Object)
    self:remove(Object)
    self:insert(Object)
end

--- Instantiates a new QuadTree. Nothing else to say
function QuadTree.new(x, y, w, h, maxDepth, maxObjects)

    local builder = {
        maxDepth = maxDepth,
        maxObjects = maxObjects,
        x = x,
        y = y,
        width = w,
        height = h,
        centerX = w / 2,
        centerY = h / 2,
        nodes = nil,
        numObjects = 0,
        objects = {},
        isSplit = false
    }

    -- Builder pattern? I hardly know her.
    setmetatable(builder, {__index = QuadTree})

    return builder
end

-- You know double clicking and holding are unique input types because they're technically fake. 
-- I need to do extra processing in order to allow for them since their related events don't actually expand that far (For example holding. There's events for clicking, releasing, and dragging, but that doens't inherently make holding.) 
local navTypesLUT = {
    click = "onClicked",
    release = "onRelease",
    doubleClick = "onDoubleClicked",
    drag = "onDrag",
    held = "onHeld",
    focus = "onFocus",
    unfocus = "onUnfocused",
    scroll = "onScroll",
}

local maxDepth = 8
local maxObjectsInNode = 4


local monitors = {}
local menus = {}
local dirtyNodes = {}
local watchedProperties = {}
local numProperties = 0

local function watchProperty(object, property, callback)
    if type(callback) ~= "function" or type(object) ~= "table" then
        return false
    end

    local objProperty = {
        propertyName = property,
        callback = callback,
        object = object,
        value = object[property]
    }

    numProperties = numProperties + 1
    watchedProperties[numProperties] = objProperty

    return numProperties -- The ID of the property
end
local function flagNodeDirty(object)
    if object.menu ~= nil then
        object.menu.quadNodesDirty = true
    end

    if not object.nodeDirty then
        table.insert(dirtyNodes, object)
    end
    object.nodeDirty = true
end

local function refreshDirtyNodes()
    for i,v in ipairs(dirtyNodes) do
        v:recomputeNode()
        v.nodeDirty = false
    end
    dirtyNodes = {}
end

local focused = nil

    local monitorTapLength = 300
    local doubleClickLeniency = 250 -- in MS.
    local lastClickTime = 0
    local lastClickType = 0
    local lastClickObj = nil

    local lastFocusObj

    local mouseButtonsDown = {}

    local function calculateClickedObjects(x,y, monitor)

        refreshDirtyNodes()

        local clickedObjects = {}

        if menus[monitor] ~= nil then
            for i,v in pairs(menus[monitor]) do
                local _, candidateObjects = v.quadTrees[monitor]:grab(x,y)
                local clickedObj

                for i2,v2 in pairs(candidateObjects) do
                    -- Grouping it like this does nothing. It's just a mental seperation
                    if (v2.x <= x and v2.y <= y) and (v2.x + v2.w > x and v2.y + v2.h > y) then
                        local thisZ,thatZ,thisDepth,thatDepth

                        thisZ = v2.objRef.absolutes.z
                        thisDepth = v2.objRef.depth
                        if clickedObj ~= nil then
                            thatZ = clickedObj.absolutes.z
                            thatDepth = clickedObj.depth
                        end
                        
                        if thisZ ~= nil and thisDepth ~= nil then
                            if (clickedObj == nil or ((thisZ > thatZ or (thisZ == thatZ and thisDepth >= thatDepth))) and v2.objRef.focusable and (v2.objRef.computedStyle.focusable == nil or v2.objRef.computedStyle.focusable)) then
                                clickedObj = v2.objRef
                            end
                        end
                    end
                end

                table.insert(clickedObjects, clickedObj)
            end

            return clickedObjects
        end

        return nil
    end

    local function handleMouseUp(_ev, button, x,y)
        if type(mouseButtonsDown[button]) == "table" then
            local buttonObj = mouseButtonsDown[button]
            buttonObj:fireEvent(navTypesLUT.release, button, x - buttonObj.absolutes.x + 2, y - buttonObj.absolutes.y + 2)
        end

        mouseButtonsDown[button] = nil

        -- Can't wait to make animations with this. (lying)
    end

    -- A lot of this is mostly just to manage focus. Focus is a hard topic...
    local function handleMouseClick(_ev, button, x,y, monitor)

        monitor = monitor or "0"

        if mouseButtonsDown[button] ~= nil then
            handleMouseUp(_ev, button, x, y)
        end

        -- Mark the button as down for held detection and some drag detection
        mouseButtonsDown[button] = true

        -- Get the menu object we clicked on.
        local clickedObjs = calculateClickedObjects(x,y, monitor)

        local clickedObj = clickedObjs ~= nil and clickedObjs[1] or nil

        if clickedObj == nil then
            return
        end

        -- Unlike focusing. Any new click defocuses old stuff.
        if lastFocusObj ~= nil then
            lastFocusObj:fireEvent(navTypesLUT.unfocus)
        end

        -- The top set just means the button is down. If theres an object then something is 'held'
        mouseButtonsDown[button] = clickedObj

        if clickedObj.focusable then
            lastFocusObj = clickedObj
            clickedObj:fireEvent(navTypesLUT.focus)
        end

        clickedObj:fireEvent(navTypesLUT.click, button, x - clickedObj.absolutes.x + 2, y - clickedObj.absolutes.y + 2)

        local leniency = monitor == "0" and doubleClickLeniency or doubleClickLeniency + monitorTapLength
        -- Prevent double clicks from being registered if they take too long or aren't the same click type
        if clickedObj == lastClickObj and lastClickType == button and os.epoch("utc") - lastClickTime <= leniency then
            lastClickTime = 0 -- Reset the clicks to make it not fire double click again on triple clicks
            
            clickedObj:fireEvent(navTypesLUT.doubleClick, button, x - clickedObj.absolutes.x + 2, y - clickedObj.absolutes.y + 2)
        end

        lastClickObj = clickedObj
        lastClickTime = os.epoch("utc")
        lastClickType = button
        return clickedObj
    end

    local function handleDrag(_ev, button, x,y)

        if type(mouseButtonsDown[button]) == "table" then
            local buttonObj = mouseButtonsDown[button]
            buttonObj:fireEvent(navTypesLUT.drag, button, x - buttonObj.absolutes.x + 2, y - buttonObj.absolutes.y + 2, x, y)
        end
        -- Click and drag support? Only if you want that.
    end

    local mUpTimer = nil -- This allows simulating holds by just accepting spam clicks as holds.
    local lastTouchPos = nil -- For 'dragging'
    local moveLeniency = 3 -- 3 px of leniency in either direction 
    local hasDragged = false
    local obj
    local function handleMonitorTouch(_ev, monitor, x, y)
        -- Manhattan distance? In this economy? Fuck.
        if lastTouchPos == nil or (not hasDragged and (math.abs(x - lastTouchPos.x) <= moveLeniency and math.abs(y - lastTouchPos.y) <= moveLeniency)) then
            obj = handleMouseClick(_ev, 1, x, y, monitor)
            lastTouchPos = {x = x, y = y}
        else
            hasDragged = true
            mouseButtonsDown[1] = obj
            handleDrag(_ev, 1, x, y)
        end

        if mUpTimer ~= nil then
            mUpTimer:Cancel()
        end

        _, mUpTimer = coreInstance:queueTimer(monitorTapLength, function ()
            hasDragged = false
            lastTouchPos = nil
            mouseButtonsDown[1] = obj
            obj = nil
            handleMouseUp(_ev, 1, x, y)
        end)
    end

    local function handleScroll(_ev, dir, x, y)
        -- Focus? no.
        
        -- Get the menu object we clicked on.
        local clickedObjs = calculateClickedObjects(x,y, "0")

        local clickedObj = clickedObjs ~= nil and clickedObjs[1] or nil

        if clickedObj == nil then
            return
        end

        clickedObj:fireEvent(navTypesLUT.scroll, dir, x - clickedObj.absolutes.x + 2 , y - clickedObj.absolutes.y + 2)
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
    local function computeNumericalUnit(object, givenNum, valueName, refObject)
        if type(givenNum) == "string" then
            -- There should not be three or more matches
            local num, unit, err = givenNum:match("^(-?%d+%.?%d*)%s*(.*)$")
 
            if err then
                return givenNum, false
            end

            num = tonumber(num)

            -- This is another type of parsing failure.
            if type(num) ~= "number" then
                return givenNum, false
            end

            unit = string.lower(unit)
            
            -- Can I please have switch statements? Please?
                
            local df = function ()
                return num
            end

            -- Ah the switchboard. Like a switch statement but worse. Let me go home
            local unitSwitchBoard = {
                px = df, cm = df, mm = df, ["in"] = df, pc = df, em = df, ex = df, ch = df, rem = df,
                pt = function ()
                    return math.ceil(num / 12)
                end,
                vw = function ()
                    -- fun fact. You need a viewport to use this unit. I know. Surprising
                    if object.menu ~= nil and object.menu.style ~= nil then
                        return math.floor((num * (object.menu.style.width * 0.01)) + .5)
                    end
                    -- Try not to crash in user space, ey?
                    return num, false
                end,
                vh = function ()
                    if object.menu ~= nil and object.menu.style ~= nil then
                        return math.floor((num * (object.menu.style.height * 0.01)) + .5)
                    end
                    
                    return num, false
                end,
                vmin = function ()
                    if object.menu ~= nil and object.menu.style ~= nil then
                        local vmin = object.menu.style.width < object.menu.style.height and object.menu.style.width or object.menu.style.height
                        return math.floor((num * (vmin * 0.01)) + .5)
                    end
                    return num, false
                end,
                vmax = function ()
                    if object.menu ~= nil and object.menu.style ~= nil then
                        local vmax = object.menu.style.width > object.menu.style.height and object.menu.style.width or object.menu.style.height
                        return math.floor((num * (vmax * 0.01)) + .5)
                    end
                    return num, false
                end,
                ["%"] = function ()
                    if refObject == nil then
                        if object.parent ~= nil then
                        if object.parent.computedStyle ~= nil and object.parent.computedStyle[valueName] then
                            local added = object.parent.computedStyle[valueName]
                            if valueName == "x" then
                                added = object.parent.computedStyle.width or computeNumericalUnit(object.parent, givenNum, "width")
                            elseif valueName == "y" then
                                added = object.parent.computedStyle.height or computeNumericalUnit(object.parent, givenNum, "height")
                            end

                            return math.floor((num * ((added) * 0.01)) + .5)
                        end

                        -- I did not realize I was signing up for recursion. Oops.
                        return math.floor((num * (computeNumericalUnit(object.parent, object.parent.style[valueName] or givenNum, valueName) * 0.01)) + .5)
                        else
                            -- Oh god theres no absolute value. Guess it's viewport
                            if valueName == "width" or valueName == "w" or valueName == "x" then
                                if object.monitor ~= nil then
                                    return computeNumericalUnit(object, num .. "vw")
                                end
                            elseif valueName == "height" or valueName == "h" or valueName == "y" then
                                if object.monitor ~= nil then
                                    return computeNumericalUnit(object, num .. "vh")
                                end
                            end
                            -- Okay so we have NOTHING. Absolutely nothing. Parsing failure
                            return givenNum, false
                        end
                    else
                        return math.floor((num * (refObject.computedStyle[valueName] * 0.01)) + .5)
                    end
                end
            }

            -- *Switch* board? like Switch statement????
            if unitSwitchBoard[unit] ~= nil then
                return unitSwitchBoard[unit]()
            else
                -- It was probably just a number in an unrelated string. Return it unmodified,
                return givenNum, false
            end
        end

        return givenNum, false
    end

    -- We internally need our colors to be a number. eg. 0x0f2fac
    local function parseColor(aColor)
        if type(aColor) == "string" then
            -- Hex
            if string.sub(aColor, 1,1) == "#" then
                aColor = tonumber(string.sub(aColor, 2), 16)
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
        -- I can't change the names easily now so I'll just explain what this all means.
        -- The parent is just your class. You copy it's fields and take them as your own.
        -- Object is you. This is the object everything is applied to and what you'll use after running this
        -- Inherited is your parent class. We instantiate it and it acts as your super. (Though note that your class is a more direct super)

        -- I don't know how to explain this in a comment. Please refer to the docs on inheritance.

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

    local function fireEventRecursive(eventObj, eventName, path, cancelled, ...)
        -- Oh right. I guess I should explain architectural decisions.
        -- Firing parent events should happen after firing your own. However if you don't have that event you still need to bubble it up
        -- This does lead to some code duplication but it's worth it to have the item the event applies to run first rather than parent down which I think is less untuitive.

        table.insert(path, eventObj)

        local shouldBubble = eventObj.parent ~= nil and type(eventObj.parent.fireEvent) == "function"
        if type(eventObj.events[eventName]) ~= "table" then
            if shouldBubble then
                fireEventRecursive(eventObj.parent, eventName, path, cancelled, ...) -- Do I know the rules of ...? No not really. I'm just adlibbing here.
            end
            
            return false, {msg = "Event does not exist.", cancelled = cancelled}
        end

        eventObj.hooks.onEvent(eventName, cancelled, ...)

        local cancel = false
        if not cancelled then
            for i,v in pairs(eventObj.events[eventName]) do
                if type(v) == "function" then
                        cancel = cancel or v(eventObj, eventName, path, ...)
                end
            end
        end

        if shouldBubble and not cancel then
            fireEventRecursive(eventObj.parent, eventName, path, cancel, ...)
        end

        return true, {cancelled = (not cancelled) and cancel or cancelled}
    end


    --Entity Component System? Yeah I don't know what that means, but I hope you find what you're looking for.

    -- Menus and menu objects are seperate, but in theory almost everything will derive from this object
    local MenuObjectBuilder = {}

    function MenuObjectBuilder.new()
        local builder = {
            -- These are post unit compute. They're stored in styles until unit compute
            x = 1,
            y = 1,
            z = 1,
            w = 0,
            h = 0,
            menu = nil,
            gObject = BedrockGraphics.objectBase:new(),
            computedStyle = {},
            stylesDirty = true,
            autoCalcNav = true,
            focused = false,
            focusable = false,
            visible = true, -- Yes UI objects are visible by default.
            parent = nil, -- bubble up events to parents.
            children = {},
            navigations = {}, -- The directions and their associatedbuttons
            events = {}, -- this is spiraling out of control fast... Whatever I need it feature filled.
        }

        builder.style = {
            x = builder.x,
            y = builder.y,
            ["z-index"] = builder.z,
            width = builder.w,
            height = builder.h,
            focusable = false,
            visible = true,
        }

        builder.absolutes = {
            x = builder.x,
            y = builder.y,
            z = builder.z
        }

        setmetatable(builder, {__index = MenuObjectBuilder, __name = "mObject"})

        coreInstance:createHook(builder, "onEvent")

        for i,v in pairs(navTypesLUT) do
            coreInstance:createHook(builder, v)
            builder:registerEvent(v, function (obj, event, ...)
                -- Look I use the metatable __call, and I have no idea how to check if it's callable. This is probably my best middleground. Besides it only false negatives, not false positives.
                if type(obj.hooks) == "table" and (type(obj.hooks[event]) == "function" or (type(obj.hooks[event]) == "table" and type(getmetatable(obj.hooks[event]).__call) == "function")) then
                    obj.hooks[event](...)
                end
            end)
        end

        -- FOCUS. PAY ATTENTION.
        builder:addEventCallback(navTypesLUT.focus, function (obj, name, path, ...)
            if #path == 1 then
                builder.focused = true
            end
        end)

        builder:addEventCallback(navTypesLUT.unfocus, function (obj, name, path, ...)
                builder.focused = false
        end)

        builder:recalculateStyles()

        return builder
    end

-- Recalculating styles? I prefer reticulating splines.
    function MenuObjectBuilder:recalculateStyles(style)
        -- One branch is recalculating one style and propagating to children the other is for all styles. Efficiency
        if style == nil then
            if self.parent ~= nil and self.parent.style ~= nil then
                -- What. Styles cascade. That's just a thing.
                for i,v in pairs(self.parent.style) do
                    if self.style[i] == nil then
                        self.style[i] = v
                    end
                end
            end

            for i,v in pairs(self.style) do
                local result

                    result = computeNumericalUnit(self, v, i)
                    if type(result) ~= "number" then
                        result = parseColor(v)
                        if type(result) ~= "number" then
                            result = v
                        end
                    end
                local prev = self.computedStyle[i]
                local success = pcall(self.gObject.setStyle, self.gObject, i, result)
                if(success) then
                self.computedStyle[i] = result
                else
                    pcall(self.gObject.setStyle, self.gObject, i, prev)
                end
            end
        else
            if self.style[style] == nil then
                if self.parent ~= nil and self.parent.style ~= nil then
                        self.style[style] = self.parent.style[style]
                end
            end

            local result = computeNumericalUnit(self, self.style[style], style)

                if type(result) ~= "number" then
                    result = parseColor(self.style[style])
                    if type(result) ~= "number" then
                        result = self.style[style]
                    end
                end

            local prev = self.computedStyle[style]
            local success = pcall(self.gObject.setStyle, self.gObject, style, result)
            if(success) then
            self.computedStyle[style] = result
            else
                pcall(self.gObject.setStyle, self.gObject, style, prev)
            end
        end

        if self.parent ~= nil then
        self.absolutes = {
            x = (self.parent.absolutes.x or 0) + (self.computedStyle.x or 0),
            y = (self.parent.absolutes.y or 0) + (self.computedStyle.y or 0),
            z = (self.parent.absolutes.z or 0) + (self.computedStyle["z-index"] or 0)
        }

        flagNodeDirty(self) -- Quad tree? in the modern era? It's more likely than you'd think
        end


        if self.children ~= nil then
            for i,v in pairs(self.children) do
                v:recalculateStyles(style)
            end
        end
    end

    function MenuObjectBuilder:recomputeNode()
        if not self.pauseNodeRecompute then
            if type(self.menu) == "table" then

                if self.quadNode ~= nil --[[and self.focusable]] then
                    self.quadNode.x = self.absolutes.x
                    self.quadNode.y = self.absolutes.y
                    self.quadNode.w = self.computedStyle.width
                    self.quadNode.h = self.computedStyle.height
                    self.quadNode.objRef = self

                    self.menu.quadTrees[self.menu.dom.trackedMonitors[1]]:refreshNode(self.quadNode)
                else
                    local quadNode = {
                        x = self.absolutes.x,
                        y = self.absolutes.y,
                        w = self.computedStyle.width,
                        h = self.computedStyle.height,
                        objRef = self,
                    }
                    self.quadNode = quadNode
                    self.menu.quadTrees[self.menu.dom.trackedMonitors[1]]:insert(self.quadNode)
                end
            else
                if self.parent ~= nil and self.menu ~= nil then
                    error("Menu is of an incorrect type.", 2)
                end
            end
        else
            return false
        end
    end

    -- As most things are in this framework, this position is relative to your parent
    function MenuObjectBuilder:setPosition(x,y,z)

        self:SetX(x):SetY(y):SetZ(z)

        flagNodeDirty(self)
        return self
    end

    function MenuObjectBuilder:setText(text)
        if type(self.gObject) ~= "table" then
            print(self)
            read()
        end
        self.gObject:setText(text)
        return self
    end

    function MenuObjectBuilder:setX(value)
        if value ~= nil then
            self.style.x = value
            self:recalculateStyles("x")
        end

        return self
    end
    function MenuObjectBuilder:setY(value)
        if value ~= nil then
            self.style.y = value
            self:recalculateStyles("y")
        end

        return self
    end
    function MenuObjectBuilder:setZ(value)
        if value ~= nil then
            self.style["z-index"] = value
            self:recalculateStyles("z-index")
        end

        return self
    end

    function MenuObjectBuilder:setSize(w,h)
        if w ~= nil then
            self.style.width = w
            self:recalculateStyles("width")
        end
        if h ~= nil then
            self.style.height = h
            self:recalculateStyles("height")
        end

        return self
    end

    function MenuObjectBuilder:setColors(textColor, bgColor)
        self:setBackgroundColor(bgColor):setTextColor(textColor)
        return self, true
    end

    function MenuObjectBuilder:setBackgroundColor(color)
        self.style.color = color
        self.style.bgColor = color
        
        self:recalculateStyles("color")
        self:recalculateStyles("bgColor")
        return self
    end

    function MenuObjectBuilder:setTextColor(color)
        self.style.textColor = color

        self:recalculateStyles("textColor")
        return self
    end

    function MenuObjectBuilder:show()
        self.style.visible = true
        self:enable()

        self:recalculateStyles("visible")
        return self
    end
    function MenuObjectBuilder:hide()
        self.style.visible = false
        self:disable()

        self:recalculateStyles("visible")
        return self
    end

    -- Enabling makes it focusable and visible if not.
    function MenuObjectBuilder:enable()
        if self.visible then
            self.gObject:enable()
        end
            self.focusable = true
            self.style.focusable = true
            
            self:recalculateStyles("focusable")
        return self
    end

    -- Disabling does not make it invisible but does disable focus
    function MenuObjectBuilder:disable()
        if self.focusable ~= false then
            self.focusable = false
            self.style.focusable = false
            
            self:recalculateStyles("focusable")
        end
        return self
    end

    --- Watching a property makes it to where if you modify that property a callback will be fired at the start of the next frame.
    function MenuObjectBuilder:watchProperty(property, callback)
        return watchProperty(self, property, callback)
    end

    function MenuObjectBuilder:unwatchProperty(id)
        if watchedProperties[id] ~= nil and watchedProperties[id].object == self then
        watchedProperties[id] = nil
        return true
        end

        return false
    end

    local function recursiveReMenu(Object, parent)

        Object.menu = parent.menu

        Object.depth = (parent.depth or 0) + 1

        if type(Object.children) ~= "table" then
            return
        end

        for i,v in pairs(Object.children) do
            recursiveReMenu(v, Object)
        end
    end

    function MenuObjectBuilder:addChild(Object)
        Object.parent = self

        if Object.quadNode then
            if Object.menu ~= nil and Object.menu.quadTrees ~= nil then
                Object.menu.quadTrees[self.menu.dom.trackedMonitors[1]]:remove(Object.quadNode)
            end
            Object.quadNode = nil
        end

        table.insert(self.children, Object)

        recursiveReMenu(Object, self)

        self.gObject:addChild(Object.gObject)

        self:recalculateStyles()

        if Object.menu ~= nil and Object.menu.quadTrees ~= nil then

            Object.quadNode = {
                x = Object.absolutes.x,
                y = Object.absolutes.y,
                w = Object.computedStyle.width,
                h = Object.computedStyle.height,
                objRef = Object
            }

            Object.menu.quadTrees[self.menu.dom.trackedMonitors[1]]:insert(Object.quadNode)
        end
        
        return self
    end

    -- Isn't it fun how that one works out.
    function MenuObjectBuilder:setParent(Object)
        Object:addChild(self)
        return self
    end

    function MenuObjectBuilder:fireEvent(eventName, ...)
        fireEventRecursive(self, eventName, {}, false, ...)
        return self
    end

    function MenuObjectBuilder:registerEvent(eventName, ...)
        local callbacks = {...}
        local overwritten = nil
        
        if self.events[eventName] ~= nil then
            if type(self.events[eventName]) == "table" then
                return false, {msg = "Naming conflict!"}
            end
            overwritten = self.events[eventName] -- I dunno. Some people are dumb and put incorrect data into places.
        end

        self.events[eventName] = {}

        local disalloweds = {}
        local failed = false
        for i,v in pairs(callbacks) do
            if type(v) == "function" then
                table.insert(self.events[eventName], v)
            else
                failed = true
                table.insert(disalloweds, v)
            end
        end

        return self,  true, {anyFailures = failed, numFailures = #disalloweds, disalloweds = disalloweds, overwrote = overwritten ~= nil, overwritten = overwritten}
    end

    function MenuObjectBuilder:addEventCallback(eventName, ...)
        if self.events[eventName] == nil then
            return self, false, {msg = "Event doesn't exist?"}
        end

        for i,v in pairs({...}) do
            table.insert(self.events[eventName], v)
        end

        return self, true
    end

    local MenuBuilder = {}

    -- Use a DOM from bedrockGraphics only.
    --- Instantiates a new menu instance. This is similar to a DOM from web development, but can be nested unlike a DOM.
    --- Typically though, you should never nest menus unless you have a good reason to. Another similar concept could be UI Canvases from Unity
    function MenuBuilder:new(DOM)
        -- Pre checks.

        if type(DOM) ~= "table" or getmetatable(DOM).__name ~= "DOM" then
            return false, "DOM provided was invalid."
        end

        local mon = _G.peripheralManager.connectedDevicesUnsorted[DOM.trackedMonitors[1]]

        local builder = {
            -- These are post unit compute. They're stored in styles until unit compute
            x = DOM.x,
            y = DOM.y,
            z = DOM.z,
            w = mon.width,
            h = mon.height,
            dom = DOM,
            gObject = BedrockGraphics.objectBase:new():setSize(mon.width, mon.height):setParent(DOM),
            style = {},
            -- TEMP COLORS; CHANGE LATER
            color = 0xfcfcfc,
            isTint = false, -- Whether the modifier colors are absolute or just a tinting of `color`
            autoCalcNav = true,
            focused = false,
            focusable = true,
            visible = true, -- Yes UI objects are visible by default.
            parent = nil, -- bubble up events to parents. Though realistically that shouldn't happen with the root element. Whatever.
            children = {},
            events = {},
            depth = 0 -- Used in some hit testing and whatnot to define where events should start. Highest depth wins. 
        }
        -- In computercraft __name has a meaning. It actually modifies tables 'names' when they're tostringed. Basically if I print it it'll be 'Menu: (address)' instead of 'Table: (address)'
        -- Peripheral types use this to show differently and to check. So I figured I'd plagiarize. As all good coders do.
        setmetatable(builder, {__index = self, __name = "Menu"})

        builder.style = {
            x = builder.x,
            y = builder.y,
            ["z-index"] = 0,
            width = builder.w,
            height = builder.h,
            color = builder.color,
            --textColor = colors.packRGB(term.nativePaletteColor(colors.black))
        }

        builder.absolutes = {
            x = builder.x - 1,
            y = builder.y - 1,
            z = builder.z - 1,
        }

        builder.computedStyle = builder.style

        builder.menu = builder

        coreInstance:createHook(builder, "onEvent")

        coreInstance:createHook(builder, navTypesLUT.focus)
        builder:registerEvent(navTypesLUT.focus, function (obj, event, ...)
            -- Look I use the metatable __call, and I have no idea how to check if it's callable. This is probably my best middleground. Besides it only false negatives, not false positives.
            if type(obj.hooks) == "table" and (type(obj.hooks[event]) == "function" or (type(obj.hooks[event]) == "table" and type(getmetatable(obj.hooks[event]).__call) == "function")) then
                obj.hooks[event](...)
            end
        end)

        builder.gObject:setBackgroundColor(builder.color)

        -- Hey look. My personal hell. Well whatever...
        builder.quadTrees = {}

        -- Quick lookup for monitors by name
        for i,v in ipairs(DOM.trackedMonitors) do
            -- The unsorted device table just stores devices by name which is what the dom uses as references. Though for a different reason.
            monitors[v] = _G.peripheralManager.connectedDevicesUnsorted[v]
            local resizeFunc = monitors[v].onResize
            monitors[v].onResize = function (...)
                resizeFunc(...)
                builder:setSize(monitors[v].width, monitors[v].height)
            end
            if type(menus[v]) ~= "table" then
                menus[v] = {}
            end

            builder.quadTrees[v] = QuadTree.new(builder.x, builder.y, builder.w, builder.h, maxDepth, maxObjectsInNode)
            table.insert(menus[v], builder) -- This is important because this is what decides which quadtrees we should query. We query all quadtrees on the monitor that has been clicked, but not ones on other monitors. That'd be wasteful.
        end

        return builder
    end
    function MenuBuilder:addChild(Object)

        if Object.quadNode then
            if Object.menu ~= nil and Object.menu.quadTrees ~= nil then
                Object.menu.quadTrees[Object.menu.dom.trackedMonitors[1]]:remove(Object.quadNode)
            end
            Object.quadNode = nil
        end

        table.insert(self.children, Object)
        Object.parent = self

        recursiveReMenu(Object, self)

        self.gObject:addChild(Object.gObject)

        Object:recalculateStyles()

        if Object.menu ~= nil and Object.menu.quadTrees ~= nil then
            Object.quadNode = {
                x = Object.absolutes.x,
                y = Object.absolutes.y,
                w = Object.computedStyle.width,
                h = Object.computedStyle.height,
                objRef = Object
            }
            Object.menu.quadTrees[Object.menu.dom.trackedMonitors[1]]:insert(Object.quadNode)
        end

        return self
    end
    function MenuBuilder:setParent(Object)
        Object:addChild(self)
        return self
    end

    -- Menus themselves assume pixel inputs. They can't support the full dynamic sizing.
    function MenuBuilder:setPosition(x, y)
        self.x = x
        self.y = y

        self.absolutes = {
            x = x,
            y = y,
            z = self.absolutes.z or 0
        }

        for i,v in pairs(self.children) do
            v:setPosition(v.x, v.y)
        end

        self.quadTrees[self.menu.dom.trackedMonitors[1]]:resize(self.absolutes.x, self.absolutes.y, self.computedStyle.w, self.computedStyle.h)
        return self
    end

    function MenuBuilder:setSize(w, h)
        self.w = w
        self.computedStyle.width = w
        self.h = h
        self.computedStyle.height = h
        self.gObject:setSize(w,h)

        self.quadTrees[self.menu.dom.trackedMonitors[1]]:resize(self.absolutes.x, self.absolutes.y, w, h)

        for i,v in pairs(self.children) do
            v:recalculateStyles()
        end

        return self
    end

    function MenuBuilder:enable()
        
        return self
    end
    function MenuBuilder:disable()
        
        return self
    end

    -- ... is for args here  
    -- You know I deal with a lot of recursion these days. Is it supposed to be common? I thought people were supposed to be scared of it...
    function MenuBuilder:fireEvent(eventName, ...)
        fireEventRecursive(self, eventName, {}, false, ...)
    end

    --- ... is for callbacks here
    function MenuBuilder:registerEvent(eventName, ...)
        local callbacks = {...}
        local overwritten = nil
        
        if self.events[eventName] ~= nil then
            if type(self.events[eventName]) == "table" then
                return false, "Naming conflict!"
            end
            overwritten = self.events[eventName] -- I dunno. Some people are dumb and put incorrect data into places.
        end

        self.events[eventName] = {}

        local disalloweds = {}
        local failed = false
        for i,v in pairs(callbacks) do
            if type(v) == "function" then
                table.insert(self.events[eventName], v)
            else
                failed = true
                table.insert(disalloweds, v)
            end
        end

        return true, {anyFailures = failed, numFailures = #disalloweds, disalloweds = disalloweds, overwrote = overwritten ~= nil, overwritten = overwritten}
    end

    function MenuBuilder:setBackgroundColor(color)
        self.computedStyle.color = color
        self.gObject:setBackgroundColor(color)
        return self
    end

    local ScrollBarBuilder = {}
    function ScrollBarBuilder:new()
        local builder = {
            backgroundObj = MenuObjectBuilder:new(),
            scrollHandle = MenuObjectBuilder:new(),
            scrollMin = 0,
            scrollMax = 0,  -- SET THESE LATER
            scrollCurrent = 0,
        }
        
        inheritFromInstance(self, builder, MenuObjectBuilder)
        
        builder:enable()

        -- This is obvious, but forgetting it would be disasterous.
        builder.backgroundObj:setParent(builder):setSize("100%", "100%")
        builder.scrollHandle:setParent(builder.backgroundObj)

        return builder
    end

    function ScrollBarBuilder:computeHandleSize()
        
        return self
    end

    local ScrollAreaBuilder = {}

    -- It's mostly just a basic menu object that scrolls
    function ScrollAreaBuilder:new()
        -- Derivation is based.
        local builder = {
            scrollbarObject = ScrollBarBuilder:new(), -- TODO
            body = {},
            scrollPos = 0
        }

        inheritFromInstance(ScrollAreaBuilder, builder, MenuObjectBuilder)
        
        builder:addEventCallback(navTypesLUT.scroll, function ()
            -- TODO
        end)

        return builder
    end

    local ButtonBuilder = {}
    
    local function handleTinting(colorA, colorB, opacity)
        local r1,g1,b1 = colors.unpackRGB(colorA)
        local r2,g2,b2 = colors.unpackRGB(colorB)

        local normalizedAlpha = (opacity / 255) -- normalization seems like a really vague term. What makes something more 'normal'

        return (colors.packRGB(((r1 * normalizedAlpha) + (r2 * (1 - normalizedAlpha))), (g1 * normalizedAlpha) + (g2 * (1 - normalizedAlpha)), (b1 * normalizedAlpha) + (b2 * (1 - normalizedAlpha))))
    end

    local function calculateButtonColor(object)
        if not object.deactivated then
            if object.defaultColor == nil then
                return
            end

            if object.pressed then
                if object.pressedColor == nil or object.pressedAlpha == nil then
                    return
                end
                if not object.isTint then
                    object.__index.__index:setBackgroundColor(parseColor(object.pressedColor))
                else
                    object.__index.__index:setBackgroundColor(handleTinting(object.pressedColor, object.defaultColor, object.pressedAlpha))
                end
            else
                object.__index.__index:setBackgroundColor(object.defaultColor)
            end
        else
            if object.deactivatedColor == nil then
                return
            end

            if not object.isTint then
                object.__index.__index:setBackgroundColor(object.deactivatedColor)
            else
                if object.deactivatedAlpha == nil then
                    return
                end 
                object.__index.__index:setBackgroundColor(handleTinting(object.deactivatedColor, object.defaultColor, object.deactivatedAlpha))
            end
        end
    end

    function ButtonBuilder.new()
        local builder = {
            onClickEvents = {},
            pressedColor = 0x0,
            pressedAlpha = 0x99,
            deactivatedColor = 0x0,
            deactivatedAlpha = 0x77,
            isTint = true,
            deactivated = false,
            pressed = false,
        }

        inheritFromInstance(ButtonBuilder, builder, MenuObjectBuilder)

        builder:enable()

        builder.defaultColor = builder.computedStyle.color or 0xCCCCCC

        builder:setBackgroundColor(builder.defaultColor)

        builder:addEventCallback(navTypesLUT.click, function (obj, name, path, button, x, y)
            -- Accept only events that happen directly to us and only left clicks
            if #path == 1 and button == 1 and not builder.deactivated then
                builder.pressed = true

                calculateButtonColor(builder)

                for _,v in pairs(obj.onClickEvents) do
                    v(x, y)
                end
            end
        end)

        builder:addEventCallback(navTypesLUT.release, function (obj, name, path, button, x, y)
            if button == 1 then
                builder.pressed = false
                calculateButtonColor(builder)
            end
        end)

        return builder
    end

    function ButtonBuilder:addOnClick(...)
        for i,v in pairs({...}) do
            table.insert(self.onClickEvents, v)
        end

        return self
    end

    function ButtonBuilder:removeOnClick(id)
        table.remove(self.onClickEvents, id)
        return self
    end

    function ButtonBuilder:enable()
        self.deactivated = false

        calculateButtonColor(self)

        return self.__index.__index:enable()
    end

    function ButtonBuilder:disable()
        self.deactivated = true
        self.focused = false

        calculateButtonColor(self)

        return self.__index.__index:disable()
    end

    function ButtonBuilder:setBackgroundColor(color)
        self.defaultColor = parseColor(color)
        calculateButtonColor(self)
        return self
    end

    local TextInputBuilder = {}

    local function recalcTextColor(builder)
        if builder.focused then
            builder.__index.__index:setTextColor(builder.textColor)
        else
            builder.__index.__index:setTextColor(handleTinting(builder.unfocusedColor, builder.textColor, builder.unfocusedAlpha))
        end
    end
    function TextInputBuilder.new()
        local builder = {
            storedText = "",
            cursorPos = 1, -- Cursor pos in a text box just refers to where we type
            seekPos = 1, -- Seek in a text box refers to the first character we show in a long 'string'
            onValueChanged = {},
            onSubmit = {},
            unfocusedColor = 0xFFFFFF,
            unfocusedAlpha = 0x85,
            
        }

        inheritFromInstance(TextInputBuilder, builder, ButtonBuilder)

        builder:enable()

        builder:registerEvent("onValueChanged", function (obj, name, path, oldVal, newVal)
            if #path == 1 then
                for i,v in ipairs(builder.onValueChanged) do
                    v(oldVal, newVal)
                end
            end
        end)

        builder:registerEvent("onSubmit", function (obj, name, path, val)
            if #path == 1 then
                for i,v in ipairs(builder.onSubmit) do
                    v(val)
                end
            end
        end)

        builder.onValueChanged.addListener = function (callback)
            table.insert(builder.onValueChanged, callback)
        end

        builder.onValueChanged.removeListener = function (id)
            id = id or #button.onValueChanged
            table.remove(builder.onValueChanged, id)
        end
        builder.onSubmit.removeListener = function (id)
            id = id or #button.onSubmit
            table.remove(builder.onSubmit, id)
        end
        builder.onSubmit.addListener = function (callback)
            table.insert(builder.onSubmit, callback)
        end

        builder:setBackgroundColor("#CCCCCC").gObject:setStyle("textAlign", "topleft")

        -- Char can only represent typing inputs. This excludes inputs such as backspace, arrow keys, and a few others you'd use for a fully featured typing experience
        local _, ev = coreInstance:registerEvent("char", function (_ev, char)
            -- Man this inheritance makes this easy.
            if builder.focused then
            local prev = builder.storedText
            local leftHalf = string.sub(builder.storedText, 1, builder.cursorPos - 1) or ""
            local rightHalf = string.sub(builder.storedText, builder.cursorPos) or ""
            builder.storedText = (leftHalf .. char .. rightHalf)
            builder.cursorPos = builder.cursorPos + #char

            end
        end)

        local _, ev2 = coreInstance:registerEvent("key", function (_ev, key)
            if builder.focused then
                if key == keys.backspace then
                    local prev = builder.storedText
                    local leftHalf = ""

                    if builder.cursorPos > 2 then
                        leftHalf = string.sub(builder.storedText, 1, (builder.cursorPos >= 2) and builder.cursorPos - 2 or 1) or ""
                    end
                    
                    local rightHalf = string.sub(builder.storedText, builder.cursorPos) or ""

                    builder.storedText = leftHalf .. rightHalf
                    builder.cursorPos = builder.cursorPos - 1 >= 1 and builder.cursorPos - 1 or 1
                elseif key == keys.delete then
                    local prev = builder.storedText
                    local leftHalf = ""

                    if builder.cursorPos > 2 then
                        leftHalf = string.sub(builder.storedText, 1, (builder.cursorPos >= 1) and builder.cursorPos - 1 or 1) or ""
                    end
                    
                    local rightHalf = string.sub(builder.storedText, builder.cursorPos + 1) or ""

                    builder.storedText = leftHalf .. rightHalf
                    builder:fireEvent("onValueChanged", prev, builder.storedText)
                elseif key == keys.left then
                    builder.cursorPos = builder.cursorPos - 1 >= 1 and builder.cursorPos - 1 or 1
                elseif key == keys.right then
                    builder.cursorPos = builder.cursorPos + 1 <= #builder.storedText + 1 and builder.cursorPos + 1 or #builder.storedText
                    builder:recalcPortion()
                -- these assume a single line text box. I'll make them more robust eventually.
                elseif key == keys.up then
                    builder.cursorPos = 1
                elseif key == keys.down then
                    builder.cursorPos = #builder.storedText + 1
                elseif key == keys.enter then
                    builder:fireEvent("onSubmit", builder.storedText)
                end

            end
        end)

        builder:addOnClick(function (x,y)
            local strLen = #builder.storedText > 0 and #builder.storedText or 1
            builder.cursorPos = builder.seekPos + x <= strLen and builder.seekPos + x or strLen + 1
        end)

        builder:watchProperty("storedText", function (prev)
           builder:recalcPortion()
            builder:fireEvent("onValueChanged", prev, builder.storedText)
        end)
        
        builder:watchProperty("seekPos", function() builder:recalcPortion() end)
        builder:watchProperty("cursorPos", function() builder:recalcPortion() end)
        builder:watchProperty("focused", function() recalcTextColor(builder) end)

        builder:setTextColor(0x10101f)

        return builder
    end

    function TextInputBuilder:recalcPortion()
        if self.cursorPos > self.seekPos + self.computedStyle.width then
            -- Increment by however much over we are
            self.seekPos = self.seekPos + 1
        elseif self.seekPos >= self.cursorPos then
            self.seekPos = self.seekPos - 1
        end

        self:setText(string.sub(self.storedText, self.seekPos, self.seekPos + self.computedStyle.width))
    end

    function TextInputBuilder:setSize(width, height)

        self.__index.__index:setSize(width, height)

        self:setText(string.sub(self.storedText or "", self.seekPos, self.w) or "")

        return self
    end

    function TextInputBuilder:setTextColor(color)
        self.textColor = color
        recalcTextColor(self)

        return self
    end

    local ProgressBarBuilder = {}

    function ProgressBarBuilder.new()
        -- no bg obj because this thing is inherently visible
        local builder = {
            progress = 0,
            progressMax = 100,
            fillObj = MenuObjectBuilder.new(),
            onValueChanged = {},
        }
        -- Instantiation in this economy? Low key what did you expect. This is a ECS like UI framework
        inheritFromInstance(ProgressBarBuilder, builder, ButtonBuilder)

        builder.computedStyle.progress = builder.progress
        builder.computedStyle.progressMax = builder.progressMax

        builder.fillObj:setParent(builder):setBackgroundColor("#DFFFDF"):disable()

        builder:recalcFill()

        -- Events are fancy.
        builder:registerEvent("onValueChanged", function (obj, name, path, oldVal, newVal)
            if #path == 1 then
                for i,v in ipairs(builder.onValueChanged) do
                    v(oldVal, newVal)
                end
            end
        end)

        builder.onValueChanged.addListener = function (callback)
            table.insert(builder.onValueChanged, callback)
        end

        builder.onValueChanged.removeListener = function (id)
            id = id or #button.onValueChanged
            table.remove(builder.onValueChanged, id)
        end

        local calcFill = function (x,y)
            -- Your progress is a function of your x in relation to the width.
            -- The X provided here is relative to the object. Which makes calcs simpler.
            
            local progPrev = builder.progress
            builder.progress = (x - 1) / (builder.computedStyle.width or 1) * builder.progressMax
            builder.progress = builder.progress <= builder.progressMax and builder.progress or builder.progressMax
            builder.progress = builder.progress >= 0 and builder.progress or 0
            builder.computedStyle.progress = builder.progress
        end

        builder:watchProperty("progress", function ()
            builder:recalcFill()
            builder:fireEvent("onValueChanged")
        end)

        builder:addOnClick(calcFill)

        builder:addEventCallback(navTypesLUT.drag, function(obj, name, path, button, x, y)
            if #path == 1 and button == 1 then
                calcFill(x,y)
            end
        end)
        return builder
    end

    function ProgressBarBuilder:recalcFill()
        if self.progress == nil or self.progressMax == nil then
            return
        end

        if self.progress == 0 then
            self.fillObj:hide()
        else
            self.fillObj:show()
            local size = (((self.progress) / self.progressMax) * 100)
            size = size > 0 and size or 0
            local sizeStr = size .. "%"

            self.fillObj:setSize(sizeStr, "100%")
        end
        return self
    end

    function ProgressBarBuilder:setMax(num)
        -- I figured I should make this function do something other than basic setting. So it supports CSS units. Fuck you
        self.progressMax = computeNumericalUnit(self, num, "progressMax", self)
        self.computedStyle.progressMax = self.progressMax

        self:recalcFill()
        return self
    end

    function ProgressBarBuilder:setSize(w, h)
        self.__index:setSize(w,h) -- Do the super call
        self:recalcFill() -- recalc the fill
        return self
    end

    local ToggleButtonBuilder = {}

    function ToggleButtonBuilder.new()
        local builder = {
            toggled = false,
            onValueChanged = {},
        }

        inheritFromInstance(ToggleButtonBuilder, builder, ButtonBuilder)

        builder:setSize(1,1)

        -- Events are fancy.
        builder:registerEvent("onValueChanged", function (obj, name, path, newVal)
            builder:repaint()
            if #path == 1 then
                for i,v in ipairs(builder.onValueChanged) do
                    v(newVal)
                end
            end
        end)

        builder.onValueChanged.addListener = function (callback)
            table.insert(builder.onValueChanged, callback)
        end

        builder.onValueChanged.removeListener = function (id)
            id = id or #button.onValueChanged
            table.remove(builder.onValueChanged, id)
        end

        builder:addOnClick(function (x,y)
            builder.toggled = not builder.toggled
            builder:fireEvent("onValueChanged", builder.toggled)
        end)

        return builder
    end

    function ToggleButtonBuilder:repaint()
        if self.toggled then
            self.__index.__index:setText("X")
        else
            self.__index.__index:setText(" ")
        end
        return self
    end

    -- A toggle button or radio button cannot be used to directly display text
    function ToggleButtonBuilder:setText()
        return self
    end



    local function init(modules, core)
        coreInstance = core
        BedrockGraphics = modules["Graphics"]
        BedrockInput = modules["Input"]
    end

    local function main(deltaTime)
        for i,v in pairs(mouseButtonsDown) do
            if type(v) == "table" then
                v:fireEvent(navTypesLUT.held, i)
            end
        end
        for i,v in pairs(watchedProperties) do
            if v.object[v.propertyName] ~= v.value then
                local prev = v.value
                v.value = v.object[v.propertyName]
                v.callback(prev)
            end
        end
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
                {
                    eventName = "mouse_click",
                    eventFunction = handleMouseClick
                },
                {
                    eventName = "monitor_touch",
                    eventFunction = handleMonitorTouch
                },
                {
                    eventName = "mouse_drag",
                    eventFunction = handleDrag
                },
                {
                    eventName = "mouse_scroll",
                    eventFunction = handleScroll
                },
                {
                    eventName = "mouse_up",
                    eventFunction = handleMouseUp
                },
            },
            
            dependencies = {
                requirements = {
                    {moduleName = "Core", version = "*"},
                    {moduleName = "Graphics", version = "0.3.0", operand = ">="},
                    {moduleName = "Input", version = "*"}
                },
                optional = {

                },
                conflicts = {

                }
            },
            version = "0.4.0",
            priority = 1,
        },
        menuObjectBuilder = MenuObjectBuilder,
        menuBuilder = MenuBuilder,
        scrollAreaBuilder = ScrollAreaBuilder,
        scrollBarBuilder = ScrollBarBuilder,
        buttonBuilder = ButtonBuilder,
        textInputBuilder = TextInputBuilder,
        progressBarBuilder = ProgressBarBuilder,
        toggleButtonBuilder = ToggleButtonBuilder,
        handleTinting = handleTinting,
        inheritFromInstance = inheritFromInstance,
    }

    return BedrockUI