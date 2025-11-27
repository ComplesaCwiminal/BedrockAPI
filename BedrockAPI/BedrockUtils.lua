 --[[+----------------------------------------------------------+
    |                     UTILS MODULE                          |
    |                    +------------+                         |
    |   What this module handles: Misc. Utilities for general   |
    |                        uses                               |
    | This module provides a bunch of utilities that other      |
    | modules tend to need. These'll likely be found in other   |
    | util libraries, but these are the defaults that modules   |
    | should use.                                               |
    +-----------------------------------------------------------+]]

    -- Start High
    local maxLayers = 25
    local maxCircles = 5


    -- If this works correctly this should preserve table and metatable relationships, too.
    local function copyTableRecursive(origTable, deep, copies, layer, circles)
        -- If `copies` isn't initialized then initialize it ourself
        copies = copies or {}

        -- Clamp minimums and enforce types
        layer = type(layer) == "number" and layer or 0
        layer = layer >= 0 and layer or 0

        circles = type(circles) == "number" and circles or 0
        circles = circles >= 0 and circles or 0

        if copies[origTable] ~= nil then
            circles = circles + 1
        end

        -- Avoids going in circles endlessly.
        if layer > maxLayers then
            return false, "Too many layers deep! Possibly circular?"
        end
        if circles > maxCircles then
            return false, "Circular reference in table: " .. tostring(origTable)
        end
        
        -- Yes you can only copy a table if it is a table.
        if type(origTable) ~= "table" then
            return false, "provided object is not a table!"
        end

        local copy = {}

        if not deep then
            -- Simple shallow copy
            for i,v in pairs(origTable) do
                copy[i] = v
            end

        else

            copies[origTable] = copy

            -- Copy the metatable, if one exists
            local origMt = getmetatable(origTable)
            local mt = {}
            if origMt then
                mt = copyTableRecursive(origMt, true, copies, layer + 1)
                setmetatable(copy, mt)
            end

            -- Recursively copy all key-value pairs
            for i, v in pairs(origTable) do
                -- I sometimes put things like __index in the regular table, too, because it kind of acts like a `super` or `base` keyword.
                -- While still being very flexible.

                if origMt ~= nil and origTable[i] == origMt[i] then
                    copy[i] = mt[i]
                elseif type(v) == "table" then
                    copy[i] = copyTableRecursive(v, true, copies, layer + 1)
                else
                    copy[i] = v
                end
            end

        end

        return copy
    end

    local function copyTable(origTable, deep)
        return copyTableRecursive(origTable, deep)
    end

    local function setMaximumLayers(num)
        if num > 0 then
            maxLayers = num
        else
            return false, "Number must be greater than 0!"
        end
    end


    --- Searches a table for an object and returns it if it exists
    --- @param tbl table
    ---@param x any
    ---@param recurse boolean -- Whether to check the top most table or also those within the table.
    ---@return string | number | false
    ---@return any
    ---@return table | nil -- The route to get to the value (or that taken before failing)
    ---@return table | nil -- The table containing the value
    local function findTableValueRecursive(tbl, x, recurse, copies, layers, circles)

        copies = copies or {}

        -- Clamp minimums and enforce types
        layers = type(layers) == "table" and layers or {}

        circles = type(circles) == "number" and circles or 0
        circles = circles >= 0 and circles or 0


        if #layers > maxLayers then
            return false, "Too many layers deep! Possibly circular?", layers, tbl
        end

        local paths = {}

        if copies[tbl] ~= nil then
            circles = circles + 1
        else 
            circles = (circles - 1 > 0) and circles or 0
        end

        if circles > maxCircles then
            return false, "Circular reference in table:", layers, tbl
        end
        
        for i, v in pairs(tbl) do

            if v == x then
                return i, v, (recurse and layers or nil), tbl
            elseif recurse and type(v) == "table" then
                paths[i] = v
            end
        end

        if recurse then
            copies[tbl] = tbl
            for i,v in pairs(paths) do
                local copy = layers
                table.insert(copy, i)
                local isFound = table.pack(findTableValueRecursive(v, x, recurse, copies, copy, circles))
                if isFound[1] ~= false or isFound[2] ~= nil then
                    return table.unpack(isFound)
                end
            end

            return false, nil, layers
        end
        
        return false, nil,layers
    end

    local function findTableValue(table, x, recurse)
        return findTableValueRecursive(table, x, recurse)
    end

    local function inheritFromInstance(class, obj, parent)
        
        -- Instantiate our parent. Ideally with new(), but just duplicate if impossible.
        local success, parentValues = pcall(function () return parent:new() end)

        if success then
            -- Deep copy the class to avoid tampering mishaps.
            local classCopy = copyTable(class, true)

            classCopy.__index = parentValues
            setmetatable(classCopy, {__index = parentValues})

            -- Allow access to it without the metatable. If used correctly, it should act like `super`.
            obj.__index = classCopy
            setmetatable(obj, {__index = classCopy})


            -- Hopefully you have no values, but if you do, then we just return them.
            return true, obj, parentValues
        end
        return false
    end

    local BedrockUtils = {}

        BedrockUtils = {
        type = "BedrockModule",
        moduleDefinition = {
            Init = init,
            Main = main,
            Cleanup = cleanup,
            moduleName = "Utils",
            events = {
            },
            
            dependencies = {
                requirements = {
                    {moduleName = "Core", version = "*"},
                },
                optional = {

                },
                conflicts = {

                }
            },
            version = "0.0.0",
            priority = 1,
        },
        CopyTable = copyTable,
        FindTableValue = findTableValue,
        InheritFromInstance = inheritFromInstance,
    }

    return BedrockUtils