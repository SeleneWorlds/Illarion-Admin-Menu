local DataKeys = require("illarion-script-loader.server.lua.lib.datakeys")
local DataFields = require("illarion-script-loader.server.lua.lib.dataFields")
local Registries = require("selene.registries")
local ItemEntity = require("illarion-script-loader.server.lua.lib.itemEntity")
local Forms = {}

local function copy(value)
    if type(value) == "userdata" then value = value:toTable() end
    local result = {}
    for key, field in pairs(value or {}) do result[key] = field end
    return result
end

function Forms.at(dimension, coordinate)
    local entries, schema, values, labels = {}, {}, {}, {}
    for _, entity in ipairs(dimension:getEntitiesAt(coordinate)) do
        if entity:hasTag("illarion:item") then
            local data = entity:getRuntimeData(DataKeys.Item)
            local field = "item" .. (#entries + 1)
            local title = entity:getEntityDefinition():getName()
            local item = Registries.findByMetadata("illarion:items", "id", entity:getEntityDefinition():getMetadata("itemId"))
            local entrySchema = {
                item = { type = "registry", registry = "illarion:items" },
                count = { type = "integer", min = 1 },
                quality = { type = "integer", min = 0 },
                wear = { type = "integer", min = 0 },
                data = "any",
            }
            local entryValues = {
                item = item and item:getName() or "",
                count = tonumber(data[DataFields.Count]) or 1,
                quality = tonumber(data[DataFields.Quality]) or 333,
                wear = tonumber(data[DataFields.Wear]) or 0,
                data = copy(data[DataFields.Data]),
            }
            table.insert(entries, { entity = entity, field = field, title = title,
                schema = entrySchema, values = entryValues })
            schema[field] = { type = "object", properties = entrySchema }
            values[field] = entryValues
            labels[field] = title
        end
    end
    if #entries == 0 then return nil end
    if #entries == 1 then schema, values = entries[1].schema, entries[1].values end
    return {
        title = #entries == 1 and "Item (" .. entries[1].title .. ")" or "Items",
        schema = schema, values = values, fieldLabels = labels,
        update = function(newValues)
            local present = {}
            for _, entity in ipairs(dimension:getEntitiesAt(coordinate)) do
                present[entity:getNetworkId()] = true
            end
            local updates = {}
            -- Validate every item before changing any runtime data.
            for index, entry in ipairs(entries) do
                assert(present[entry.entity:getNetworkId()], "Item no longer exists at this coordinate.")
                local value = #entries == 1 and newValues or newValues[entry.field]
                assert(type(value) == "table", "Item values must be an object.")
                assert(type(value.item) == "string" and value.item ~= "", "An item is required.")
                local item = assert(Registries.findByName("illarion:items", value.item), "Unknown item: " .. value.item)
                local definition = assert(Registries.findByMetadata("entities", "itemId", item:getMetadata("id")),
                    "No item entity exists for: " .. value.item)
                for _, field in ipairs({ "count", "quality", "wear" }) do
                    local number = value[field]
                    assert(type(number) == "number" and number % 1 == 0
                        and number >= (field == "count" and 1 or 0) and number <= 2147483647,
                        field .. " must be a " .. (field == "count" and "positive" or "non-negative") .. " 32-bit integer.")
                end
                assert(type(value.data) == "table", "Item data must be an object.")
                for key in pairs(value.data) do assert(type(key) == "string", "Item data must be an object.") end
                updates[index] = { value = value, definition = definition }
            end
            for index, entry in ipairs(entries) do
                local entity = entry.entity
                local update = updates[index]
                local value = update.value
                local oldEntity
                if update.definition:getName() ~= entity:getEntityDefinition():getName() then
                    local replacement = ItemEntity.Create(update.definition)
                    replacement:setCoordinate(entity:getCoordinate())
                    oldEntity = entity
                    entity = replacement
                end
                local data = entity:getRuntimeData(DataKeys.Item)
                data[DataFields.Count], data[DataFields.Quality], data[DataFields.Wear] = value.count, value.quality, value.wear
                data[DataFields.Data] = copy(value.data)
                if oldEntity then
                    oldEntity:despawn()
                    entity:spawn(dimension)
                    entry.entity = entity
                end
                entity:updateVisuals()
            end
        end,
    }
end

return Forms
