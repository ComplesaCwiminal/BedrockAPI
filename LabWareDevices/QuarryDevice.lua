local deviceDescriptor = {}
local coreInstance

local x,y,z
local fuelLimit
local slot
local automataPeriph = nil -- We need this because it allows us to act like a player. Does that make us weaker or stronger. Who tf knows.

local skipInvRecalcs = false

local blockLUTs = {
    -- This one is to correlate block tags to item tags 
    blockTagToolDict = {
        ["minecraft:mineable/pickaxe"] = "minecraft:pickaxes",
        ["minecraft:mineable/axe"] = "minecraft:axes",
        ["minecraft:mineable/shovel"] = "minecraft:shovels",
        ["minecraft:mineable/hoe"] = "minecraft:hoes",
    },
    uniquesLUT = {
        chests = {
            chest = "minecraft:chest"
        },
        interactibles = {
            -- TODO
        }
    }
}


local itemLUTs = {
    fuelsLUT = {
        coal = "minecraft:coal",
        charcoal = "minecraft:charcoal",
        lava = "minecraft:lava_bucket",
    },
    -- This one is to find any tools in the inventory
    toolsTagLUT = {
        tools = "c:tools",
        pickaxes = "minecraft:pickaxes",
        axes = "minecraft:axes",
        shovels = "minecraft:shovels",
        hoes = "minecraft:hoes"
    }

}

local inventory = {
    slots = {},
    items = {},
    tools = {},
}

-- I'm thinking we use two a* passes. one to decide the chunks we go through. The other to decide how we pass through said chunks.
    -- If the second pass fails then we select the second best fitting path from the first. and so on until we either run out of known chunks or it works.

-- Yeah I have no idea if I can compress this but I'll try.
local map = {
    knowns = {},
    chunks = {},
    uniques = {
        interactibles = {},
        chests = {},
        undesirables = {}, -- Undesirables are things that are unmineable or conversely cannot be entered due to danger.
    }, -- Uniques are blocks you can interact with. Though they aren't 'interactables', if only because chests and interactables are categorized differently.
}

local state = {
    contacting = {},
    map = map,
    chests = map.uniques.chests,
    bounds = {}, -- format is x,y,z,w,h,d
    lastMined = {}, -- format is x,y,z, block
    nextToMine = {}, -- format is x,y,z. 
    chunkDone = true,
    desiredPos = {}, -- Do I really need to tell you the format? 
    rotation = "unknown", -- Can you figure out what this is?
    homeCoord = {},
    runState = "stopped"
}




local function rollover(val, max, min)
    return (((val - min) % (max - min)) + (max - min)) % (max - min) + min -- lmao I have no idea what I just wrote.
end

local function updateSlot(slotNum, inDepth)
    local prev = inventory.slots[slotNum]
    local cur = turtle.getItemDetail(slotNum, inDepth)

    local toolLost = false
    if inDepth then
        for i,v in pairs(itemLUTs.toolsTagLUT) do
            if type(cur) == "table" and type(cur.tags) == "table" then
                -- Avoid double inserting, but if it exist but didn't previously meet the requirements then insert anyway.
                if cur.tags[v] ~= nil and ((type(prev) ~= "table" or type(prev.tags) ~= "table") or prev.tags[v] == nil) then
                    if type(inventory.tools[v]) ~= "table" then
                        inventory.tools[v] = {}
                    end

                    table.insert(inventory.tools[v], slotNum)
                end
            elseif type(prev) == "table" and type(prev.tags) == "table" then
                if prev.tags[v] ~= nil then
                    toolLost = true
                    break
                end
            end
        end
        
        if toolLost then
            for i,v in pairs(inventory.tools) do
                if prev.tags[v] ~= nil then
                    for i2,v2 in pairs(inventory.tools[i]) do
                        if slotNum == v2 then
                            table.remove(inventory.tools[i], i2)
                            break
                        end
                    end
                end
            end
        end
    end

    if (prev ~= nil and cur == nil) or (prev ~= nil and cur ~= nil and prev.name ~= cur.name) then
        for i,v in pairs(inventory.items[prev.name]) do
            if v == slotNum then
                table.remove(inventory.items[prev.name], i)
                break
            end
        end
    end

    if cur ~= nil then
        if type(inventory.items[cur.name]) ~= "table" then
            inventory.items[cur.name] = {}
        end
        table.insert(inventory.items[cur.name], slotNum)
    end

    inventory.slots[slotNum] = cur
end

local function useItem(item, amount)
    if inventory.items[item] ~= nil then
        local maxIdx = #inventory.items[item]
        local itemSlot = inventory.items[item][maxIdx]
        local itemObj = inventory.slots[itemSlot]
        itemObj.count = itemObj.count - amount

        if itemObj.count <= 0 then
            inventory.slots[itemSlot] = nil
            inventory.items[item][maxIdx] = nil -- Reverse traversal makes this safe. Love you.
        end
        return true, itemSlot, itemObj.count
    end
    return false
end

local function rotate(direction)
    print(state.rotation)
    local lut = {
        left = function ()
            turtle.turnLeft()
            state.rotation = rollover(state.rotation - 90, 360, 0)
        end,
        right = function ()
            turtle.turnRight()
            state.rotation = rollover(state.rotation + 90, 360, 0)
        end,
    }
    if lut[direction] ~= nil then
        lut[direction]()
        return true
    end
    return false
end

local function getCoordFromSide(side)
    -- These are in world coordinates. Can't wait to learn coordinate transformations for this shit.
    local lut = {
        top = {0,1,0},
        bottom = {0,-1,0},
        front = {0,0,-1},
        back = {0,0,1},
        left = {-1,0,0},
        right = {1,0,0}
    }

    if lut[side] == nil then
        return false, "Invalid Side"
    end

    local rotatedTransform = lut[side]
    
    -- If I knew I'd be doing this I wouldn't have been born.
    local rotation = math.rad(state.rotation)

    if state.rotation ~= 0 and state.rotation ~= 180 then
    local matrix = {}
    -- You know... Not a fan of the confusing coordinate space -z is +y... probably. Doesn't matter for this coordinate transformation, but it made the LUT harder.
    matrix[1] = math.floor(rotatedTransform[1] * math.cos(rotation) - rotatedTransform[3] * math.sin(rotation) + .5)
    matrix[2] = rotatedTransform[2]
    matrix[3] = math.floor(rotatedTransform[1] * math.sin(rotation) + rotatedTransform[3] * math.cos(rotation) + .5)

    rotatedTransform = matrix
    elseif state.rotation == 180 then
        rotatedTransform[1] = (rotatedTransform[1]) * -1
        rotatedTransform[3] = (rotatedTransform[3]) * -1
    end
    local coords = table.pack(x,y,z)
    for i,v in pairs(rotatedTransform) do
        coords[i] = coords[i] + v
    end

    return table.unpack(coords)
end

local function mapBlock(block, side)
    local nX,nY,nZ = getCoordFromSide(side)

    if nX ~= false then
        state.contacting[side] = block

        map.knowns[(nX .. " " .. nY .. " " .. nZ)] = block
    end



    -- There will only be one match in v, but there might be many in the LUT as a whole.
    for i,v in pairs(blockLUTs.uniquesLUT) do
        for i2,v2 in pairs(v) do
            if block.name == v2 then
                if map.uniques[i2] == nil then
                    map.uniques[i2] = {}
                end
                table.insert(map.uniques[i2], (nX .. " " .. nY .. " " .. nZ))
                break
            end
        end
    end
    return nX, nY, nZ
end

local function formatInspect(isBlock, block)
    return isBlock and block or {name = "air", state = {}, tags = {}}
end

local function checkContacts()
    mapBlock(formatInspect(turtle.inspect()), "front")
    mapBlock(formatInspect(turtle.inspectUp()), "up")
    mapBlock(formatInspect(turtle.inspectDown()), "down")
end

local function getMoveFromSide(side)
    local lut = {
        top = function ()
            x,y,z = getCoordFromSide("top")
            turtle.up()
            checkContacts()
        end,
        bottom = function ()
            x,y,z = getCoordFromSide("bottom")
            turtle.down()
            checkContacts()
        end,
        front = function ()
            x,y,z = getCoordFromSide("front")
            turtle.forward()
            checkContacts()
        end,
        back = function ()
            x,y,z = getCoordFromSide("back")
            turtle.back()
            checkContacts()
        end,
        left = function ()
            x,y,z = getCoordFromSide("left")
            turtle.turnLeft()
            turtle.forward()
            state.rotation = rollover(state.rotation - 90, 360, 0)
            checkContacts()
        end,
        right = function ()
            x,y,z = getCoordFromSide("right")
            turtle.turnRight()
            turtle.forward()
            state.rotation = rollover(state.rotation + 90, 360, 0)

            checkContacts()
        end
    }
    lut.up = lut.top
    lut.down = lut.bottom
    lut.forward = lut.front
    lut.backward = lut.back
    
    return lut[side] ~= nil, lut[side]
end

local function move(direction)
    -- Error handling? I'm too tired tbh
    if state.runState == "stopped" then
        local success, func = getMoveFromSide(direction)
        if success then
            func()
            print(x,y,z)
            print(state.rotation)
        end
    else
        deviceDescriptor.events.onError("You cannot move a running quarrier")
    end
end

local function mine()
    local isBlock, origBlock = turtle.inspect()
    local failure
    local block = origBlock

    if isBlock then
        local hasTool = false
        local x1,y1,z1 = getCoordFromSide("front")

        state.lastMined = { 
            x = x1,
            y = y1,
            z = z1,
            block = block,
        }

        -- This part is hard to explain. Basically this dict maps block tags to tools.
        for i,v in pairs(blockLUTs.blockTagToolDict) do
            -- If the key (block tag) exists within our block then..
            if origBlock.tags[i] ~= nil and inventory.tools[v] ~= nil then
                -- The any value. It means that theres a block tag that just allows any tool to mine 
                if v ~= "any" then
                    -- Select the slot that the value cooresponds to the tool and grab the last tool that applies
                    local toolSlot = inventory.tools[v][#inventory.tools[v]]
                    turtle.select(toolSlot)
                end

                hasTool = true
                break -- End early
            end
        end

        if not hasTool then
            -- If the block has no tool tags
            return false, "Missing needed tool!"
        end

        -- It may take more than one call to break a block. Quirk of the trade. Anyway hit the block until it isn't the same block anymore.
        while isBlock and not failure and origBlock.name == block.name do
            failure = not automataPeriph.digBlock()
            isBlock, block = turtle.inspect()
            os.sleep(automataPeriph.getDigCooldown and automataPeriph.getDigCooldown() or 0)
        end

        turtle.suck()
    end

    mapBlock(formatInspect(turtle.inspect()))
end

local function rotateAbsolute(direction)

    local lut = {
        north = 0,
        south = 180,
        west = 270,
        east = 90
    }
    
    local desiredDir = lut[direction]
    
    if type(direction) == "number" then
        desiredDir = direction
    end

    if desiredDir == nil then
        return false
    end

    -- Calculate the shortest difference
    local absDeg = desiredDir - state.rotation
    if absDeg > 180 then
        absDeg = absDeg - 360
    elseif absDeg < -180 then
        absDeg = absDeg + 360
    end

    for i = 1, math.floor(math.abs(absDeg) / 90) do
        if absDeg > 0 then
            turtle.turnRight()
        else
            turtle.turnLeft()
        end
    end

    state.rotation = desiredDir
    return true
end

local function moveAbsolute(direction)
    local origDir = state.rotation
    if rotateAbsolute(direction) then

        checkContacts()

        x,y,z = getCoordFromSide("front")
        
        turtle.forward()

        
        rotateAbsolute(origDir)
        checkContacts()
        
        return true
    end
    return false
end

-- Different from move in that it goes to any XYZ
local function goToPos(nX,nY,nZ)
    -- TODO.
end

-- Dunno what to name this
local function refreshInventory(_ev)
    if not skipInvRecalcs then
        local checkSlot = 1
        local success, _ = pcall(turtle.getItemDetail, checkSlot) -- Select throws when out of bounds. We exploit that.

        if success ~= nil then
            repeat
                success = pcall(turtle.getItemDetail, checkSlot)
        
                if success then
                    updateSlot(checkSlot, true)
                end

                checkSlot = checkSlot + 1
            until not success
        end
    end
    skipInvRecalcs = false
end


local function start()
    if state.runState ~= "running" then
        state.runState = "running"
        -- This should pathfind to an adjacent chunk to either it's home coordinate, it's last mined block, or the next chunk.
    else

    end
end

local function pause()
    if state.runState == "running" then
        state.runState = "paused"
        -- This should pathfind back to the home coordinate after depositing it's contents.
    else
        
    end
end

local function stop()
    if state.runState ~= "stopped" and state.runState ~= "stopping" then
        state.runState = "stopping"
        -- Pathfind DIRECTLY back to the home coordinate. Nothing else.
    else

    end
end

local function init(args)
    automataPeriph = peripheral.find("weak_automata") -- Why do THEY not adhere to case.. Kids these days.
    if turtle and automataPeriph then
        coreInstance = args.coreInstance
        x,y,z = gps.locate(5)
        if x ~= nil then
            state.homeCoord = {x=x,y=y,z=z}
            fuelLimit = turtle.getFuelLimit()
            slot = turtle.getSelectedSlot() -- We have no way of knowing the selected slot on startup 

            refreshInventory()

            for i,v in pairs(itemLUTs.fuelsLUT) do
                local success, itemSlot, count = useItem(v, 0) -- Check if the item exists

                if success then
                    turtle.select(itemSlot)
                    turtle.refuel(count)
                    updateSlot(itemSlot)
                    turtle.select(slot)
                end
            end

            -- how many times can I redefine one local before I lose the plot.
            local success = turtle.forward()

            if success then
                -- We need two samples in order to ascertain rotation. (Rotation is in 1D, so we only need one axis. Thanks GPS math for teaching me that fun fact)
                local x2,y2,z2 = gps.locate(5)

                if x2 ~= nil then
                    local deltaX, deltaZ = x2 - x, z2 - z

                    -- Treat north like it's deeply confusing (it is) (they told me y was first but -deltaZ is north so what the fuck.)
                    local radDir = math.atan2(deltaX, -deltaZ) -- No not like rad in the old person sense. It's radians.

                    state.rotation = math.floor(math.deg(radDir) + .5) -- Hopefully this math works out. Given it's a grid system it really should
                    state.rotation = state.rotation >= 0 and state.rotation or 360 + state.rotation -- Clamping to 0-360
                    
                    x,y,z = x2,y2,z2

                    checkContacts()

                    coreInstance:registerEvent("turtle_inventory", refreshInventory)
                else
                    deviceDescriptor.quit()
                    error("Lost connection to the GPS service, and cannot continue!", 0)
                end
            else
                deviceDescriptor.quit() -- Lmao error.
                error("Could not ascertain transform! (You need a free space in front of the turtle and fuel)", 0)
            end
        else
            deviceDescriptor.quit()
            error("Could not get GPS coordinates!", 0)
        end
    else
        deviceDescriptor.quit()
        error("You have to launch this on a turtle with a weak automata!", 0)
    end
end

local function main()
    -- When d'you think I'm actually gonna get around to actually making this part. Probably when I figure out how I'm gonna pathfind on unknown terrain. Fuck me, ey?
end

local function cleanup()

end


deviceDescriptor = {
    deviceType = "Quarry", -- Used mostly for grouping
    deviceName = "Quarrier MK.1",
    functions = {
        move = move,
        rotate = rotate,
        moveabsolute = moveAbsolute,
        rotateabsolute = rotateAbsolute,
        mine = mine,
        start = start,
        pause = pause,
        stop = stop,
    },
    variables = {
        fuel = {
            value = 0, -- We need to wait for init
            valueType = "number",
            getCallback = function (self)
                -- Look I don't want to track it too hard. Also it's always accurate for end users even if I fuck up.
                self.value = turtle.getFuelLevel()
                return self.value
                end,
            modifyCallback = function (self, new) return false, "Value is Read Only." end -- denied.
        },
        runState = {
            value = "stopped",
            valueType = "string",
            getCallback = function (self)
                self.value = state.runState
                return self.value
            end,
            modifyCallback = function (self)
                return false, "Value is Read Only."
            end
        }
    },
    -- Events get populated by our runner. As such we don't put anything in their bodies.
    events = {
        onError = function () end,
        onNoFuel = function () end,
        onFull = function () end,
        Log = function () end,
    },
    init = init,
    main = main,
    cleanup = cleanup,
    -- Same goes for quit when it comes to population
    quit = function ()
    end
}

return deviceDescriptor

-- Do I know how this works?
        -- No
-- Did I make almost all parts of it?
        -- Yes.