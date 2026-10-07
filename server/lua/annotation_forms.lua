local Registries = require("selene.registries")
local Config = require("selene.config")
local Forms = {}

local function copy(value)
    local result = {}
    for key, field in pairs(value) do result[key] = field end
    return result
end

local function classify(key, data, tiles)
    if key == "illarion:warp" then return "warp" end
    if key == "illarion:triggerfield" then return "triggerfield" end
    if key == "illarion:door" or data.lockId ~= nil or data.doorLock ~= nil then return "door" end
    if key == "illarion:depot" or data.depot ~= nil then return "depot" end
    for _, tile in ipairs(tiles) do
        if tile:getName() == key then
            local itemId = tile:getMetadata("itemId")
            if tonumber(itemId) == 321 or tonumber(itemId) == 4817 then return "depot" end
            local item = itemId and Registries.findByMetadata("illarion:items", "id", tonumber(itemId))
            local script = item and item:getField("script")
            if type(script) == "string" and script:match("doors$") then return "door" end
        end
    end
    return "raw"
end

local function isLegacy(kind, data)
    if kind ~= "door" and kind ~= "depot" then return false end
    -- Named VBU fields take precedence, just as they do in the runtime readers.
    if kind == "depot" and data.depot ~= nil then return false end
    if kind == "door" and (data.lockId ~= nil or data.doorLock ~= nil) then return false end
    return data.data ~= nil or Config.getProperty("useLegacyUseItem") == "true"
end

local function numericValue(value, message)
    assert(type(value) == "number" and value % 1 == 0 and value >= 0 and value <= 2147483647, message)
    return value
end

local function storedNumber(value, original)
    return type(original) == "number" and value or tostring(value)
end

local function definition(kind, data, legacy)
    if legacy then
        local values = copy(data)
        values.data = nil
        if kind == "depot" then
            values.depot = tonumber(data.data) or 0
            return { depot = { type = "integer", min = 0 } }, values
        end
        values.lockId = tonumber(data.data) or 0
        values.doorLock = tonumber(data.quality) == 233 and "unlocked" or "locked"
        return {
            lockId = { type = "integer", min = 0 },
            doorLock = { type = "enum", values = {
                { value = "locked", label = "Locked" }, { value = "unlocked", label = "Unlocked" },
            } },
        }, values
    end
    if kind == "warp" then
        return { destination = "coordinate" }, { destination = { x = data.x, y = data.y, z = data.z } }
    elseif kind == "triggerfield" then
        return { script = "script" }, copy(data)
    elseif kind == "door" then
        return {
            lockId = { type = "string", optional = true },
            doorLock = { type = "enum", optional = true, values = {
                { value = "locked", label = "Locked" }, { value = "unlocked", label = "Unlocked" },
            } },
        }, copy(data)
    elseif kind == "depot" then
        local values = copy(data)
        values.depot = tonumber(data.depot)
        return { depot = { type = "integer", min = 0 } }, values
    end
    return { data = "any" }, { data = copy(data) }
end

local function updated(kind, values, original, legacy)
    assert(type(values) == "table", "Annotation values must be an object.")
    if legacy then
        local result = copy(values)
        result.depot, result.lockId, result.doorLock = nil, nil, nil
        local value = numericValue(kind == "depot" and values.depot or values.lockId,
            kind == "depot" and "Depot ID must be a non-negative 32-bit integer."
                or "Lock ID must be a non-negative 32-bit integer.")
        -- Item.data treats a missing value as zero and removes it when zero is assigned.
        result.data = value ~= 0 and storedNumber(value, original.data) or nil
        if kind == "door" then
            assert(values.doorLock == "locked" or values.doorLock == "unlocked",
                "Door lock must be locked or unlocked.")
            local currentState = tonumber(original.quality) == 233 and "unlocked" or "locked"
            if values.doorLock ~= currentState then
                result.quality = storedNumber(values.doorLock == "unlocked" and 233 or 333, original.quality)
            end
        end
        return result
    end
    if kind == "warp" then
        local destination = values.destination
        assert(type(destination) == "table", "Destination must be a coordinate.")
        for _, axis in ipairs({ "x", "y", "z" }) do
            local value = destination[axis]
            assert(type(value) == "number" and value % 1 == 0 and math.abs(value) <= 2147483647,
                "Destination coordinates must be 32-bit integers.")
        end
        local result = copy(original)
        result.x, result.y, result.z = destination.x, destination.y, destination.z
        return result
    elseif kind == "raw" then
        assert(type(values.data) == "table", "Annotation JSON must be an object.")
        for key in pairs(values.data) do assert(type(key) == "string", "Annotation JSON must be an object.") end
        return values.data
    elseif kind == "triggerfield" then
        assert(type(values.script) == "string" and values.script ~= "", "A trigger field requires a script.")
    elseif kind == "door" then
        assert(values.lockId == nil or type(values.lockId) == "string", "Lock ID must be a string.")
        assert(values.doorLock == nil or values.doorLock == "locked" or values.doorLock == "unlocked",
            "Door lock must be locked or unlocked.")
    elseif kind == "depot" then
        assert(type(values.depot) == "number" and values.depot % 1 == 0 and values.depot >= 0
            and values.depot <= 2147483647, "Depot ID must be a non-negative 32-bit integer.")
        local result = copy(values)
        result.depot = tostring(values.depot)
        return result
    end
    return values
end

function Forms.at(dimension, coordinate)
    local annotations = dimension:getAnnotationsAt(coordinate)
    local keys = {}
    for key in pairs(annotations) do table.insert(keys, key) end
    if #keys == 0 then return nil end
    table.sort(keys)
    local tiles = dimension:getTilesAt(coordinate)
    local schema, values, labels, entries = {}, {}, {}, {}
    local titles = { warp = "Warp destination", door = "Door", depot = "Depot", triggerfield = "Trigger field", raw = "Raw JSON" }
    for index, key in ipairs(keys) do
        local kind = classify(key, annotations[key], tiles)
        local legacy = isLegacy(kind, annotations[key])
        local entrySchema, entryValues = definition(kind, annotations[key], legacy)
        local field = "annotation" .. index
        entries[index] = { key = key, kind = kind, field = field, legacy = legacy }
        if #keys == 1 then
            schema, values = entrySchema, entryValues
        else
            schema[field] = { type = "object", properties = entrySchema }
            values[field] = entryValues
            labels[field] = titles[kind] .. " (" .. key .. ")"
        end
    end
    return {
        title = #keys == 1 and titles[entries[1].kind] .. " (" .. keys[1] .. ")" or "Tile annotations",
        schema = schema, values = values, fieldLabels = labels,
        update = function(newValues)
            local updates = {}
            -- Validate every annotation before changing the map.
            for _, entry in ipairs(entries) do
                local current = dimension:getAnnotationAt(coordinate, entry.key)
                assert(current, "Annotation no longer exists: " .. entry.key)
                updates[entry.key] = updated(entry.kind, #keys == 1 and newValues or newValues[entry.field], current, entry.legacy)
            end
            for _, entry in ipairs(entries) do
                dimension:annotateTile(coordinate, entry.key, updates[entry.key])
            end
        end,
    }
end

return Forms
