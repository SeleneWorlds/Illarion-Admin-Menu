local AdminMenu = require("moonlight-admin.server.lua.admin_menu")
local Registries = require("selene.registries")
local Players = require("selene.players")
local Dimensions = require("selene.dimensions")
local DataKeys = require("illarion-script-loader.server.lua.lib.datakeys")
local DataFields = require("illarion-script-loader.server.lua.lib.dataFields")
local CharacterPersistence = require("illarion-script-loader.server.lua.lib.characterPersistence")
local AttributeManager = require("illarion-script-loader.server.lua.lib.attributeManager")
local MagicManager = require("illarion-script-loader.server.lua.lib.magicManager")
local AdminPersistence = require("illarion-script-loader.server.lua.lib.adminPersistence")
local MonsterManager = require("illarion-script-loader.server.lua.lib.monsterManager")
local CharacterManager = require("illarion-script-loader.server.lua.lib.characterManager")
local TileAnnotationForms = require("illarion-admin-menu.server.lua.annotation_forms")
local ItemForms = require("illarion-admin-menu.server.lua.item_forms")

local function raceVisual(race)
    local raceId = race:getMetadata("id")
    return raceId and string.format("illarion:races/race_%d_0", raceId) or nil
end

local function monsterVisual(monster)
    local race = Registries.findByName("illarion:races", monster:getField("race"))
    return race and raceVisual(race) or nil
end

AdminMenu.registerRegistryVisualResolver("illarion:races", raceVisual)
AdminMenu.registerRegistryVisualResolver("illarion:monsters", monsterVisual)

AdminMenu.registerRegistryVisualResolver("illarion:items", function(item)
    return item:getField("visual")
end)

AdminMenu.registerRegistryVisualResolver("illarion:gfx", function(gfx)
    return gfx:getField("visual")
end)

local function onlineCharacterOptions(initiatingPlayer)
    local options = {}
    local initiatingEntity = initiatingPlayer and initiatingPlayer:getControlledEntity()
    local initiatingCharacter = initiatingEntity and Character.fromSelenePlayer(initiatingPlayer) or nil
    for _, player in ipairs(Players.getOnlinePlayers()) do
        if player:getControlledEntity() then
            local character = Character.fromSelenePlayer(player)
            table.insert(options, {
                value = tostring(character.id),
                label = character.name,
                visual = string.format("illarion:races/race_%d_0", character:getRace()),
                default = initiatingCharacter ~= nil and character.id == initiatingCharacter.id,
            })
        end
    end
    return options
end

AdminMenu.registerTargetResolver("illarion:characters", function(player)
    local options = onlineCharacterOptions(player)
    local onlineIds = {}
    for _, option in ipairs(options) do
        onlineIds[tonumber(option.value)] = true
    end
    for _, character in ipairs(CharacterPersistence.loadAllCharacterSummaries()) do
        if not onlineIds[character.id] then
            table.insert(options, {
                value = tostring(character.id),
                label = character.name,
                visual = string.format("illarion:races/race_%d_0", character.race),
                offline = true,
            })
        end
    end
    return options
end)

local function resolveTarget(characterId)
    characterId = assert(tonumber(characterId), "Invalid character target.")
    for _, player in ipairs(Players.getOnlinePlayers()) do
        if player:getControlledEntity() then
            local character = Character.fromSelenePlayer(player)
            if character.id == characterId then
                return character, false
            end
        end
    end
    for _, character in ipairs(CharacterPersistence.loadAllCharacterSummaries()) do
        if character.id == characterId then
            return character, true
        end
    end
    error("Target character no longer exists.")
end

local function getAdminCharacter(player)
    if not player:getControlledEntity() then
        return nil
    end
    local character = Character.fromSelenePlayer(player)
    return character:isAdmin() and character or nil
end

local function getPositionInFront(character)
    local offsets = {
        [Character.north] = { x = 0, y = -1 },
        [Character.northeast] = { x = 1, y = -1 },
        [Character.east] = { x = 1, y = 0 },
        [Character.southeast] = { x = 1, y = 1 },
        [Character.south] = { x = 0, y = 1 },
        [Character.southwest] = { x = -1, y = 1 },
        [Character.west] = { x = -1, y = 0 },
        [Character.northwest] = { x = -1, y = -1 },
    }
    local offset = offsets[character:get_face_to()] or offsets[Character.north]
    return position(character.pos.x + offset.x, character.pos.y + offset.y, character.pos.z)
end

local function resolveCoordinate(character, coordinate)
    return coordinate and position(coordinate.x, coordinate.y, coordinate.z) or getPositionInFront(character)
end

local function resolveOnlineTarget(characterId)
    local character, offline = resolveTarget(characterId)
    assert(not offline, "Target character is no longer online.")
    return character
end

local function requireMessage(message)
    assert(message:find("%S"), "Message must not be empty.")
    return message
end

local function changeAdminAccess(player, targetId, grant)
    local administrator = assert(getAdminCharacter(player), "Administrator access required.")
    local target = resolveTarget(targetId)
    local userId = CharacterPersistence.getUserIdForCharacter(target.id)
    local verb = grant and "Grant Admin" or "Revoke Admin"
    administrator:logAdmin(string.format("%s: %s (%s)", verb, target.name, userId))
    local changed
    if grant then
        changed = AdminPersistence.grant(userId)
    else
        changed = AdminPersistence.revoke(userId)
    end
    if not changed then
        return string.format("%s's account was already %s.", target.name, grant and "an administrator" or "not an administrator")
    end
    return string.format("%s access for %s's account.", grant and "Granted administrator" or "Revoked administrator", target.name)
end

local moonlightEditorOk, moonlightEditor = pcall(require, "moonlight-editor.server.lua.editor")
if moonlightEditorOk then
    moonlightEditor.registerRegistryVisualResolver("illarion:races", raceVisual)
    moonlightEditor.registerRegistryVisualResolver("illarion:monsters", monsterVisual)

    local function monsterSpawnVisual(spawn)
        local monsterName = next(spawn:getField("monsters") or {})
        local monster = monsterName and Registries.findByName("illarion:monsters", monsterName)
        return monster and monsterVisual(monster) or nil
    end

    moonlightEditor.registerGizmoProvider(function()
        local gizmos = {}
        for _, spawn in pairs(Registries.findAll("illarion:monster_spawns")) do
            local coordinate = spawn:getField("coordinate")
            local id = spawn:getMetadata("id") or spawn:getName()
            table.insert(gizmos, {
                id = "illarion:monster-spawn:" .. tostring(id),
                label = spawn:getName(),
                coordinate = coordinate,
                path = spawn:getSourcePath(),
                color = "#e05252",
                visual = monsterSpawnVisual(spawn),
            })
        end
        return gizmos
    end)

    moonlightEditor.registerGizmoProvider(function(player, coordinate)
        local entity = player:getCameraEntity() or player:getControlledEntity()
        local dimension = entity and entity:getDimension()
        if not dimension then return {} end
        local gizmos = {}
        for _, entry in ipairs(dimension:getAnnotationsInRange(coordinate, 64)) do
            local coordinate = entry.coordinate
            local tiles = dimension:getTilesAt(coordinate)
            local tile = tiles[#tiles]
            local keys = {}
            for key in pairs(entry.annotations) do
                table.insert(keys, key)
            end
            table.sort(keys)
            table.insert(gizmos, {
                id = string.format("illarion:annotations:%d:%d:%d", coordinate.x, coordinate.y, coordinate.z),
                label = table.concat(keys, ", "),
                coordinate = coordinate,
                color = "#e8b84a",
                lookup = true,
                visual = tile and tile:getVisual() or nil,
            })
        end
        return gizmos
    end)

    moonlightEditor.registerGizmoProvider(function(player, coordinate)
        local camera = player:getCameraEntity() or player:getControlledEntity()
        local dimension = camera and camera:getDimension()
        if not dimension then return {} end
        local gizmos = {}
        for _, entity in ipairs(dimension:getEntitiesInRange(coordinate, 64)) do
            local entityCoordinate = entity:getCoordinate()
            local gizmoCoordinate = { x = entityCoordinate.x, y = entityCoordinate.y, z = entityCoordinate.z }
            if entity:hasTag("illarion:item") then
                local definition = entity:getEntityDefinition()
                local itemId = definition:getMetadata("itemId")
                local item = itemId and Registries.findByMetadata("illarion:items", "id", itemId)
                table.insert(gizmos, {
                    id = "illarion:item:" .. tostring(entity:getNetworkId()),
                    label = item and (item:getField("name") or item:getName()) or definition:getName(),
                    coordinate = gizmoCoordinate,
                    color = "#65b8e8",
                    lookup = true,
                    visual = item and item:getField("visual") or nil,
                })
            elseif entity:hasTag("illarion:character") then
                local data = entity:getRuntimeData(DataKeys.Character)
                if data[DataFields.CharacterType] == Character.npc then
                    local definition = data[DataFields.NPC]
                    local raceId = tonumber(data[DataFields.Race])
                    if not raceId and type(data[DataFields.Race]) == "string" then
                        local race = Registries.findByName("illarion:races", data[DataFields.Race])
                        raceId = race and tonumber(race:getMetadata("id"))
                    end
                    table.insert(gizmos, {
                        id = "illarion:npc:" .. tostring(entity:getNetworkId()),
                        label = entity:getName(),
                        coordinate = gizmoCoordinate,
                        path = definition and definition:getSourcePath() or nil,
                        color = "#88c978",
                        visual = raceId and string.format("illarion:races/race_%d_%d", raceId,
                            data[DataFields.Sex] == "female" and 1 or 0) or nil,
                    })
                end
            end
        end
        return gizmos
    end)

    moonlightEditor.registerCoordinateLookup(function(coordinate, scope, player)
        local entity = player and (player:getCameraEntity() or player:getControlledEntity())
        local dimension = entity and entity:getDimension()
        if not scope and dimension then
            local form = ItemForms.at(dimension, coordinate)
            if form then return form end
            form = TileAnnotationForms.at(dimension, coordinate)
            if form then return form end
        end
        local function matchesScope(path)
            if not scope then return true end
            if type(path) ~= "string" then return false end
            local namespace, entry = path:match("^[^/]+/common/data/([^/]+)/[^/]+/(.+)%.json$")
            if not namespace then
                namespace, entry = path:match("^[^/]+/server/data/([^/]+)/[^/]+/(.+)%.json$")
            end
            if not namespace then return false end
            local ok, resource = pcall(Registries.findByName, scope, namespace .. ":" .. entry)
            return ok and resource and resource:getSourcePath() == path
        end
        if scope then
            local lookupDimension = dimension or Dimensions.getDefault()
            local scopedEntities = lookupDimension:getEntitiesAt(coordinate)
            for _, scopedEntity in ipairs(scopedEntities) do
                local definition = scopedEntity:getEntityDefinition()
                if matchesScope(definition:getSourcePath()) then
                    return definition:getSourcePath()
                end
                if scope == "illarion:items" then
                    local itemId = definition:getMetadata("itemId")
                    local item = itemId and Registries.findByMetadata("illarion:items", "id", itemId)
                    if item then return item:getSourcePath() end
                end
            end
            local tiles = lookupDimension:getTilesAt(coordinate)
            for i = #tiles, 1, -1 do
                local definition = tiles[i]:getDefinition()
                if matchesScope(definition:getSourcePath()) then
                    return definition:getSourcePath()
                end
                if scope == "illarion:items" then
                    local itemId = definition:getMetadata("itemId")
                    local item = itemId and Registries.findByMetadata("illarion:items", "id", itemId)
                    if item then return item:getSourcePath() end
                end
            end
        end
        local entities = Dimensions.getDefault():getEntitiesAt(coordinate)
        for _, entity in ipairs(entities) do
            if entity:hasTag("illarion:character") then
                local charData = entity:getRuntimeData(DataKeys.Character)
                local definition
                if charData[DataFields.CharacterType] == Character.npc then
                    definition = charData[DataFields.NPC]
                elseif charData[DataFields.CharacterType] == Character.monster then
                    definition = charData[DataFields.Monster]
                end
                if definition and matchesScope(definition:getSourcePath()) then
                    return definition:getSourcePath()
                end
            end
        end
        if scope and scope ~= "illarion:monster_spawns" then return nil end
        for _, spawn in pairs(Registries.findAll("illarion:monster_spawns")) do
            local spawnCoordinate = spawn:getField("coordinate")
            if spawnCoordinate and spawnCoordinate.x == coordinate.x
                and spawnCoordinate.y == coordinate.y
                and spawnCoordinate.z == coordinate.z then
                return spawn:getSourcePath()
            end
        end
        return nil
    end)

    AdminMenu.registerAction({
        id = "illarion-admin-menu:toggle-editor",
        label = "Toggle Editor",
        description = "Enter or leave the editor.",
        parameters = {},
        isAvailable = function(player)
            return getAdminCharacter(player) ~= nil
        end,
        execute = function(player)
            local enabled = moonlightEditor.toggle(player)
            return enabled and "Editor enabled." or "Editor disabled."
        end,
    })
end

AdminMenu.registerAction({
    id = "illarion-admin-menu:grant-admin",
    label = "Grant Admin",
    description = "Grant administrator access to the account that owns a character.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        return changeAdminAccess(player, parameters.target, true)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:revoke-admin",
    label = "Revoke Admin",
    description = "Revoke administrator access from the account that owns a character.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        return changeAdminAccess(player, parameters.target, false)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:broadcast-message",
    label = "Broadcast Message",
    description = "Send a message to every online player.",
    parameters = {
        { name = "message", label = "Message", type = "message" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local message = requireMessage(parameters.message)
        world:broadcast(message, message)
        administrator:logAdmin("Broadcast Message: " .. message)
        return "Broadcast message sent."
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:talk-to",
    label = "Talk to",
    description = "Send a private inform message to an online character.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
        { name = "message", label = "Message", type = "message" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local message = requireMessage(parameters.message)
        character:inform(message)
        administrator:logAdmin(string.format("Talk to %s: %s", character.name, message))
        return "Message sent to " .. character.name .. "."
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:toggle-clipping",
    label = "Toggle Clipping",
    description = "Toggle whether an online character collides with solid objects.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local enabled = not character:getClippingActive()
        character:setClippingActive(enabled)
        administrator:logAdmin(string.format("Turn %s Clipping %s", character.name, enabled and "On" or "Off"))
        return string.format("Clipping %s for %s.", enabled and "enabled" or "disabled", character.name)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:toggle-invisibility",
    label = "Toggle Invisibility",
    description = "Toggle whether an online character is visible or not.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local enabled = not character.isinvisible
        character.isinvisible = enabled
        administrator:logAdmin(string.format("Turn %s Invisibility %s", character.name, enabled and "On" or "Off"))
        return string.format("Invisibility %s for %s.", enabled and "enabled" or "disabled", character.name)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:toggle-godmode",
    label = "Toggle Godmode",
    description = "Toggle whether an online character can receive damage.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local enabled = not CharacterManager.isGodMode(character)
        CharacterManager.setGodMode(character, enabled)
        administrator:logAdmin(string.format("Turn %s Godmode %s", character.name, enabled and "On" or "Off"))
        return string.format("Godmode %s for %s.", enabled and "enabled" or "disabled", character.name)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:teleport-to-coordinate",
    label = "Teleport to Coordinate",
    description = "Teleport a character to a world coordinate.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
        { name = "coordinate", label = "Coordinate", type = "coordinate" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local target = position(parameters.coordinate.x, parameters.coordinate.y, parameters.coordinate.z)
        if offline then
            CharacterPersistence.updateOfflineCharacterPosition(character.id, target.x, target.y, target.z)
        else
            character:forceWarp(target)
        end
        administrator:logAdmin(string.format("Warp %s to Coordinate (%d, %d, %d)", character.name, target.x, target.y, target.z))
        return string.format("Warped %s to %d, %d, %d.", character.name, target.x, target.y, target.z)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:teleport-to-location",
    label = "Teleport to Location",
    description = "Teleport a character to a point of interest.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
        { name = "location", label = "Location", type = "registry", registry = "illarion:poi" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local location = assert(Registries.findByName("illarion:poi", parameters.location), "Location no longer exists.")
        local coordinate = assert(location:getField("coordinate"), "Location has no coordinate.")
        local target = position(
            assert(tonumber(coordinate.x), "Location has no X coordinate."),
            assert(tonumber(coordinate.y), "Location has no Y coordinate."),
            assert(tonumber(coordinate.z), "Location has no Z coordinate.")
        )
        local locationName = location:getMetadata("name") or parameters.location
        if offline then
            CharacterPersistence.updateOfflineCharacterPosition(character.id, target.x, target.y, target.z)
        else
            character:forceWarp(target)
        end
        administrator:logAdmin(string.format(
            "Teleport %s to %s (%d, %d, %d)",
            character.name,
            locationName,
            target.x,
            target.y,
            target.z
        ))
        return string.format("Teleported %s to %s.", character.name, locationName)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:bring",
    label = "Bring",
    description = "Bring a character to you.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        if offline then
            CharacterPersistence.updateOfflineCharacterPosition(
                character.id,
                administrator.pos.x,
                administrator.pos.y,
                administrator.pos.z
            )
        else
            character:warp(administrator.pos)
        end
        administrator:logAdmin("Bring " .. character.name)
        return "Brought " .. character.name .. "."
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:teleport-to-player",
    label = "Teleport to Player",
    description = "Teleport to another character.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local target = offline and position(character.x, character.y, character.z) or character.pos
        administrator:forceWarp(target)
        administrator:logAdmin("Teleport to Player " .. character.name)
        return "Teleported to " .. character.name .. "."
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:change-race",
    label = "Change Race",
    description = "Change a character's race.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
        { name = "race", label = "Race", type = "registry", registry = "illarion:races" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local race = assert(Registries.findByName("illarion:races", parameters.race), "Race no longer exists.")
        local raceId = assert(race:getMetadata("id"), "Race has no Illarion ID.")
        local raceName = race:getMetadata("name") or parameters.race
        if offline then
            CharacterPersistence.updateOfflineCharacterRace(character.id, raceId)
        else
            character:setRace(raceId)
        end
        administrator:logAdmin(string.format("Change %s Race to %s (%d)", character.name, raceName, raceId))
        return string.format("Changed %s's race to %s.", character.name, raceName)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:change-name",
    label = "Change Name",
    description = "Change a character's name.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
        { name = "name", label = "New Name", type = "string" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local name = parameters.name
        assert(
            #name >= 2 and #name <= 50 and not name:match("^%s") and not name:match("%s$") and not name:match("%c"),
            "Use a name of 2-50 characters without leading or trailing spaces."
        )
        local oldName = character.name
        CharacterPersistence.updateCharacterName(character.id, name)
        if not offline then
            character.SeleneEntity:setName(name)
            character.SeleneEntity:updateVisuals()
        end
        administrator:logAdmin(string.format("Change %s Name to %s", oldName, name))
        return string.format("Changed %s's name to %s.", oldName, name)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:change-sex",
    label = "Change Sex",
    description = "Change a character's sex.",
    parameters = {
        { name = "target", label = "Target", type = "target", resolver = "illarion:characters" },
        {
            name = "sex",
            label = "Sex",
            type = "enum",
            options = {
                { value = "male", label = "Male" },
                { value = "female", label = "Female" },
            },
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        local newSex = parameters.sex
        local oldSex = offline and character.sex
            or (character:increaseAttrib("sex", 0) == Character.female and "female" or "male")
        if offline then
            CharacterPersistence.updateOfflineCharacterSex(character.id, newSex)
        else
            character:setAttrib("sex", newSex == "female" and Character.female or Character.male)
            character.SeleneEntity:updateVisuals()
        end
        administrator:logAdmin(string.format("Change %s Sex from %s to %s", character.name, oldSex, newSex))
        return string.format("Changed %s from %s to %s.", character.name, oldSex, newSex)
    end,
})

local function changeSkill(player, parameters, setExact)
    local administrator = assert(getAdminCharacter(player), "Administrator access required.")
    local character, offline = resolveTarget(parameters.target)
    local skill = assert(Registries.findByName("illarion:skills", parameters.skill), "Skill no longer exists.")
    local skillId = assert(skill:getMetadata("id"), "Skill has no Illarion ID.")
    local skillName = skill:getMetadata("name") or skill:getField("name") or parameters.skill
    local oldValue, newValue
    if offline then
        oldValue, newValue = CharacterPersistence.updateOfflineCharacterSkill(
            character.id,
            skillId,
            parameters.value,
            setExact
        )
    else
        oldValue = character:getSkill(skillId)
        if setExact then
            character:setSkill(skillId, parameters.value, character:getMinorSkill(skillId))
            newValue = character:getSkill(skillId)
        else
            newValue = character:increaseSkill(skillId, parameters.value)
        end
    end
    administrator:logAdmin(string.format(
        "%s %s Skill %s from %g to %g",
        setExact and "Set" or "Adjust",
        character.name,
        skillName,
        oldValue,
        newValue
    ))
    return string.format("Changed %s's %s from %g to %g.", character.name, skillName, oldValue, newValue)
end

local skillParameters = {
    {
        name = "target",
        label = "Target",
        type = "target",
        resolver = "illarion:characters",
    },
    { name = "skill", label = "Skill", type = "registry", registry = "illarion:skills" },
}

AdminMenu.registerAction({
    id = "illarion-admin-menu:set-skill",
    label = "Set Skill",
    description = "Set a character's skill to an exact value.",
    parameters = {
        skillParameters[1],
        skillParameters[2],
        { name = "value", label = "Value", type = "number", default = 0, min = 0, max = 100 },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        return changeSkill(player, parameters, true)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:adjust-skill",
    label = "Adjust Skill",
    description = "Increase or decrease a character's skill.",
    parameters = {
        skillParameters[1],
        skillParameters[2],
        { name = "value", label = "Delta", type = "number", default = 0, min = -100, max = 100 },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        return changeSkill(player, parameters, false)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:kill",
    label = "Kill",
    description = "Kill an online character.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        character:setAttrib("hitpoints", 0)
        administrator:logAdmin("Kill " .. character.name)
        return "Killed " .. character.name .. "."
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:destroy-item-on-map",
    label = "Destroy Item on Map",
    description = "Destroy the top item stack at a coordinate, or in front of you when omitted.",
    parameters = {
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local target = resolveCoordinate(administrator, parameters.coordinate)
        local item = world:getItemOnField(target)
        assert(item.id ~= 0, "There is no item at that coordinate.")
        local itemId = item.id
        local quantity = item.number
        assert(world:erase(item, quantity), "The item could not be destroyed.")
        administrator:logAdmin(string.format(
            "Destroy %d x Item %d at Coordinate (%d, %d, %d)",
            quantity,
            itemId,
            target.x,
            target.y,
            target.z
        ))
        return string.format("Destroyed %d x item %d.", quantity, itemId)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:toggle-lock",
    label = "Toggle Lock",
    description = "Lock or unlock a door at a coordinate, or in front of you when omitted.",
    parameters = {
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local target = resolveCoordinate(administrator, parameters.coordinate)
        local item = world:getItemOnField(target)
        assert(item.id ~= 0, "There is no lock at that coordinate.")
        local locked = item.quality == 233
        item.quality = locked and 333 or 233
        if locked and item.data == 0 then
            item.data = math.random(1, 999999999)
        end
        item:setData("doorLock", locked and "locked" or "unlocked")
        world:changeItem(item)
        administrator:logAdmin(string.format(
            "%s Item %d at Coordinate (%d, %d, %d)",
            locked and "Lock" or "Unlock",
            item.id,
            target.x,
            target.y,
            target.z
        ))
        return string.format("%s item %d.", locked and "Locked" or "Unlocked", item.id)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:get-key",
    label = "Get Key",
    description = "Get a key for the lock at a coordinate, or in front of you when omitted.",
    parameters = {
        {
            name = "key",
            label = "Key",
            type = "registry",
            registry = "illarion:items",
            deferred = false,
            filter = function(item)
                return item:getField("script") == "item.keys"
            end,
        },
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local target = resolveCoordinate(administrator, parameters.coordinate)
        local item = world:getItemOnField(target)
        assert(item.id ~= 0, "There is no lock at that coordinate.")
        local lockId = item.data
        if lockId == 0 then
            lockId = math.random(1, 999999999)
            item.data = lockId
            world:changeItem(item)
        end
        local key = assert(Registries.findByName("illarion:items", parameters.key), "Key no longer exists.")
        local keyId = assert(key:getMetadata("id"), "Key has no Illarion ID.")
        local rest = administrator:createItem(keyId, 1, 333, lockId)
        assert(rest == 0, "The key could not be created because your inventory is full.")
        administrator:logAdmin(string.format(
            "Get Key for Item %d at Coordinate (%d, %d, %d), Lock ID %d",
            item.id,
            target.x,
            target.y,
            target.z,
            lockId
        ))
        return string.format("Created a key for lock %d.", lockId)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:play-effect",
    label = "Play Effect",
    description = "Play a graphical effect at a coordinate, or in front of you when omitted.",
    parameters = {
        { name = "effect", label = "Effect", type = "registry", registry = "illarion:gfx" },
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local gfx = assert(Registries.findByName("illarion:gfx", parameters.effect), "Effect no longer exists.")
        local effectId = assert(tonumber(gfx:getMetadata("gfxId")), "Effect has no numeric gfxId.")
        local target = resolveCoordinate(administrator, parameters.coordinate)
        world:gfx(effectId, target)
        administrator:logAdmin(string.format(
            "Play Effect %d at Coordinate (%d, %d, %d)",
            effectId,
            target.x,
            target.y,
            target.z
        ))
        return string.format("Played effect %d.", effectId)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:play-sound",
    label = "Play Sound",
    description = "Play a sound at a coordinate, or in front of you when omitted.",
    parameters = {
        { name = "sound", label = "Sound", type = "registry", registry = "sounds" },
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local sound = assert(Registries.findByName("sounds", parameters.sound), "Sound no longer exists.")
        local soundId = assert(tonumber(sound:getMetadata("soundId")), "Sound has no numeric soundId.")
        local target = resolveCoordinate(administrator, parameters.coordinate)
        world:makeSound(soundId, target)
        administrator:logAdmin(string.format(
            "Play Sound %d at Coordinate (%d, %d, %d)",
            soundId,
            target.x,
            target.y,
            target.z
        ))
        return string.format("Played sound %d.", soundId)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:teach-runes",
    label = "Teach all Runes",
    description = "Teach all 32 runes for a character's current magic type.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local magicType = character:getMagicType()
        for rune = 0, 31 do
            character:teachMagic(magicType, rune)
        end
        administrator:logAdmin(string.format("Teach %s All Runes for Magic Type %d", character.name, magicType))
        return string.format("Taught %s all runes for magic type %d.", character.name, magicType)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:forget-runes",
    label = "Forget all Runes",
    description = "Forget all runes for a character's current magic type.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character = resolveOnlineTarget(parameters.target)
        local magicType = character:getMagicType()
        MagicManager.ForgetAllMagic(character, magicType)
        administrator:logAdmin(string.format("Make %s Forget All Runes for Magic Type %d", character.name, magicType))
        return string.format("Made %s forget all runes for magic type %d.", character.name, magicType)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:change-magic-type",
    label = "Change Magic Type",
    description = "Change a character's magic type.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
        },
        {
            name = "magicType",
            label = "Magic Type",
            type = "registry",
            registry = "illarion:magic_types",
        },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local magicType = assert(
            Registries.findByName("illarion:magic_types", parameters.magicType),
            "Magic Type no longer exists."
        )
        local magicTypeId = assert(tonumber(magicType:getMetadata("id")), "Magic Type has no numeric ID.")
        local magicTypeName = magicType:getMetadata("name") or parameters.magicType
        local character, offline = resolveTarget(parameters.target)
        local oldMagicType
        if offline then
            oldMagicType = CharacterPersistence.updateOfflineCharacterMagicType(character.id, magicTypeId)
        else
            oldMagicType = character:getMagicType()
            character:setMagicType(magicTypeId)
        end
        administrator:logAdmin(string.format(
            "Change %s Magic Type from %d to %s (%d)",
            character.name,
            oldMagicType,
            magicTypeName,
            magicTypeId
        ))
        return string.format("Changed %s's magic type from %d to %s.", character.name, oldMagicType, magicTypeName)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:set-attribute",
    label = "Set Attribute",
    description = "Set a character's persisted base attribute.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
        },
        { name = "attribute", label = "Attribute", type = "registry", registry = "illarion:attributes" },
        { name = "value", label = "Value", type = "number" },
        { name = "overrideLimits", label = "Override Limits", type = "boolean", default = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local attributeDefinition = assert(
            Registries.findByName("illarion:attributes", parameters.attribute),
            "Attribute no longer exists."
        )
        local attribute = assert(attributeDefinition:getMetadata("key"), "Attribute has no key.")
        local attributeName = attributeDefinition:getMetadata("name") or attribute
        local isBaseAttribute = attributeDefinition:getMetadata("base") == true
        local character, offline = resolveTarget(parameters.target)
        local oldValue, newValue
        if offline then
            assert(isBaseAttribute, "Only base attributes can be changed for an offline character.")
            if not parameters.overrideLimits then
                local race = assert(
                    Registries.findByMetadata("illarion:races", "id", character.race),
                    "Race no longer exists."
                )
                local titlecaseAttribute = attribute:gsub("^%l", string.upper, 1)
                local range = race:getField(attribute)
                local minValue = range and range.min or race:getField("min" .. titlecaseAttribute)
                local maxValue = range and range.max or race:getField("max" .. titlecaseAttribute)
                assert(
                    minValue ~= nil and maxValue ~= nil
                        and parameters.value >= minValue and parameters.value <= maxValue,
                    "Value is invalid for the character's race."
                )
            end
            oldValue = CharacterPersistence.updateOfflineCharacterBaseAttribute(character.id, attribute, parameters.value)
            newValue = parameters.value
        else
            assert(isBaseAttribute, "The selected attribute is not a base attribute.")
            oldValue = character:getBaseAttribute(attribute)
            if parameters.overrideLimits then
                AttributeManager.GetAttribute(character, attribute):setValue(parameters.value)
            else
                assert(character:setBaseAttribute(attribute, parameters.value), "Value is invalid for the character's race.")
            end
            newValue = character:getBaseAttribute(attribute)
        end
        administrator:logAdmin(string.format(
            "Set %s Attribute %s from %g to %g",
            character.name,
            attributeName,
            oldValue,
            newValue
        ))
        return string.format("Set %s's %s from %g to %g.", character.name, attributeName, oldValue, newValue)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:set-attribute-temporarily",
    label = "Set Attribute temporarily",
    description = "Temporarily set an online character's effective attribute.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
        { name = "attribute", label = "Attribute", type = "registry", registry = "illarion:attributes" },
        { name = "value", label = "Value", type = "number" },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local attributeDefinition = assert(
            Registries.findByName("illarion:attributes", parameters.attribute),
            "Attribute no longer exists."
        )
        local attribute = assert(attributeDefinition:getMetadata("key"), "Attribute has no key.")
        local attributeName = attributeDefinition:getMetadata("name") or attribute
        local character = resolveOnlineTarget(parameters.target)
        local oldValue = attribute == "poisonvalue" and character:getPoisonValue()
            or character:increaseAttrib(attribute, 0)
        character:setAttrib(attribute, parameters.value)
        local newValue = attribute == "poisonvalue" and character:getPoisonValue()
            or character:increaseAttrib(attribute, 0)
        administrator:logAdmin(string.format(
            "Temporarily Set %s Attribute %s from %g to %g",
            character.name,
            attributeName,
            oldValue,
            newValue
        ))
        return string.format("Temporarily set %s's %s from %g to %g.", character.name, attributeName, oldValue, newValue)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:heal",
    label = "Heal",
    description = "Fully heal or revive an online character.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
        { name = "health", label = "Health", type = "boolean", default = true },
        { name = "hunger", label = "Hunger", type = "boolean", default = true },
        { name = "mana", label = "Mana", type = "boolean", default = true },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local character, offline = resolveTarget(parameters.target)
        assert(not offline, "Target character is no longer online.")
        local revived = parameters.health and character:increaseAttrib("hitpoints", 0) <= 0
        if parameters.health then
            character:setAttrib("hitpoints", 10000)
            character:setPoisonValue(0)
        end
        if parameters.hunger then
            character:setAttrib("foodlevel", 60000)
        end
        if parameters.mana then
            character:setAttrib("mana", 10000)
        end
        administrator:logAdmin(string.format("%s %s", revived and "Revive" or "Heal", character.name))
        return string.format("%s %s.", revived and "Revived" or "Healed", character.name)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:change-weather",
    label = "Change Weather",
    description = "Change global weather.",
    parameters = {
        { name = "cloudDensity", label = "Cloud Density", type = "number", required = false, min = 0, max = 100 },
        { name = "fogDensity", label = "Fog Density", type = "number", required = false, min = 0, max = 100 },
        { name = "windDirection", label = "Wind Direction", type = "number", required = false, min = -100, max = 100 },
        { name = "gustStrength", label = "Gust Strength", type = "number", required = false, min = 0, max = 100 },
        {
            name = "precipitationStrength",
            label = "Precipitation Strength",
            type = "number",
            required = false,
            min = 0,
            max = 100,
        },
        {
            name = "precipitationType",
            label = "Precipitation Type (0 None, 1 Rain, 2 Snow)",
            type = "number",
            required = false,
            min = 0,
            max = 2,
            step = 1,
        },
        { name = "thunderstorm", label = "Thunderstorm", type = "number", required = false, min = 0, max = 100 },
        { name = "temperature", label = "Temperature", type = "number", required = false, min = -50, max = 50 },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        if parameters.precipitationType ~= nil then
            assert(parameters.precipitationType % 1 == 0, "Precipitation Type must be an integer.")
        end
        local weather = world.weather
        local fields = {
            cloudDensity = "cloud_density",
            fogDensity = "fog_density",
            windDirection = "wind_dir",
            gustStrength = "gust_strength",
            precipitationStrength = "percipitation_strength",
            precipitationType = "percipitation_type",
            thunderstorm = "thunderstorm",
            temperature = "temperature",
        }
        local changed = false
        for parameterName, weatherField in pairs(fields) do
            if parameters[parameterName] ~= nil then
                weather[weatherField] = parameters[parameterName]
                changed = true
            end
        end
        assert(changed, "At least one weather value is required.")
        world:setWeather(weather)
        administrator:logAdmin(string.format(
            "Change Weather: clouds %g, fog %g, wind %g, gust %g, precipitation %g/%g, thunder %g, temperature %g",
            weather.cloud_density,
            weather.fog_density,
            weather.wind_dir,
            weather.gust_strength,
            weather.percipitation_type,
            weather.percipitation_strength,
            weather.thunderstorm,
            weather.temperature
        ))
        return "Changed the weather."
    end,
})

local baseTreasureOk, baseTreasure = pcall(require, "base.treasure")
if baseTreasureOk then
    AdminMenu.registerAction({
        id = "illarion-admin-menu:create-treasure-map",
        label = "Create Treasure Map",
        description = "Create a treasure map for an online character.",
        parameters = {
            {
                name = "target",
                label = "Target",
                type = "target",
                resolver = "illarion:characters",
                requireOnline = true,
            },
        },
        isAvailable = function(player)
            return getAdminCharacter(player) ~= nil
        end,
        execute = function(player, parameters)
            local administrator = assert(getAdminCharacter(player), "Administrator access required.")
            local character = resolveOnlineTarget(parameters.target)
            assert(baseTreasure.createMap(character), "No suitable treasure location could be found.")
            administrator:logAdmin("Create Treasure Map for " .. character.name)
            return "Created a treasure map for " .. character.name .. "."
        end,
    })
end

AdminMenu.registerAction({
    id = "illarion-admin-menu:give-item",
    label = "Give Item",
    description = "Give an item to an online character.",
    parameters = {
        {
            name = "target",
            label = "Target",
            type = "target",
            resolver = "illarion:characters",
            requireOnline = true,
        },
        { name = "item", label = "Item", type = "registry", registry = "illarion:items", deferred = true },
        { name = "quantity", label = "Quantity", type = "number", default = 1, min = 1, step = 1 },
        { name = "quality", label = "Quality", type = "number", default = 333, min = 0, step = 1 },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        assert(parameters.quantity % 1 == 0, "Quantity must be an integer.")
        assert(parameters.quality % 1 == 0, "Quality must be an integer.")
        local character, offline = resolveTarget(parameters.target)
        assert(not offline, "Target character is no longer online.")
        local item = assert(Registries.findByName("illarion:items", parameters.item), "Item no longer exists.")
        local itemId = assert(item:getMetadata("id"), "Item has no Illarion ID.")
        local itemName = item:getField("name")
        if itemName == nil or itemName == "" then
            itemName = parameters.item
        end
        local rest = character:createItem(itemId, parameters.quantity, parameters.quality, {})
        local given = parameters.quantity - rest
        administrator:logAdmin(string.format(
            "Give %s %d x %s (%d), Quality %d%s",
            character.name,
            given,
            itemName,
            itemId,
            parameters.quality,
            rest > 0 and string.format(" (%d did not fit)", rest) or ""
        ))
        if rest > 0 then
            return string.format("Gave %s %d x %s; %d did not fit.", character.name, given, itemName, rest)
        end
        return string.format("Gave %s %d x %s.", character.name, given, itemName)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:spawn-monster",
    label = "Spawn Monster",
    description = "Spawn a monster at a world coordinate.",
    parameters = {
        { name = "monster", label = "Monster", type = "registry", registry = "illarion:monsters" },
        { name = "coordinate", label = "Coordinate", type = "coordinate", required = false },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local monster = assert(
            Registries.findByName("illarion:monsters", parameters.monster),
            "Monster no longer exists."
        )
        local monsterId = assert(monster:getMetadata("id"), "Monster has no Illarion ID.")
        local coordinate = parameters.coordinate
        local target = coordinate and position(coordinate.x, coordinate.y, coordinate.z)
            or getPositionInFront(administrator)
        world:createMonster(monsterId, target, 0)
        administrator:logAdmin(string.format(
            "Spawn Monster %d at Coordinate (%d, %d, %d)",
            monsterId,
            target.x,
            target.y,
            target.z
        ))
        return string.format("Spawned monster %d at %d, %d, %d.", monsterId, target.x, target.y, target.z)
    end,
})

AdminMenu.registerAction({
    id = "illarion-admin-menu:despawn-monsters-in-range",
    label = "Despawn Monsters in Range",
    description = "Despawn all monsters within range of you.",
    parameters = {
        { name = "range", label = "Range", type = "number", default = 20, min = 0, step = 1 },
    },
    isAvailable = function(player)
        return getAdminCharacter(player) ~= nil
    end,
    execute = function(player, parameters)
        local administrator = assert(getAdminCharacter(player), "Administrator access required.")
        local range = parameters.range
        assert(range % 1 == 0, "Range must be an integer.")
        local monsters = world:getMonstersInRangeOf(administrator.pos, range)
        for _, monster in ipairs(monsters) do
            MonsterManager.Remove(monster.SeleneEntity)
        end
        administrator:logAdmin(string.format("Despawn %d Monsters in Range %d", #monsters, range))
        return string.format("Despawned %d monster%s.", #monsters, #monsters == 1 and "" or "s")
    end,
})
