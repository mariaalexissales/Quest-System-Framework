----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_Text"

QSF = QSF or {}
QSF_Schema = QSF_Schema or {}

local VALID_KEY = "^[%w_%.%-]+$"
local MAX_COLLECT_TYPES = 16
local MAX_CHOICE_OPTIONS = 8

local FALLBACK_OUTFIT = "Generic01"
local FACINGS = { N = true, NE = true, E = true, SE = true, S = true, SW = true, W = true, NW = true }

-- a lookup that throws means the engine is not ready yet, which is "cannot say" rather
-- than "invalid" - otherwise an early load would silently delete every objective.
local function QSF_itemExists(fullType)
    local ok, item = pcall(function() return getScriptManager():FindItem(fullType) end)
    if not ok then return true end
    return item ~= nil
end

local function QSF_perkFromName(name)
    local ok, perk = pcall(QSF_Rules.perk, name)
    if not ok then return nil, true end
    return perk, false
end

-- a placeholder nobody fills is shown as written, in front of every player, so whoever
-- wrote it is told which one.
local function QSF_checkPlaceholders(text, where, errors)
    for _, name in ipairs(QSF_Text.unknown(text)) do
        errors[#errors + 1] = where .. ": unknown placeholder {" .. name
            .. "}, so it is shown as written (there is {player}, {npc} and {quest})"
    end
end

-- outfits are listed per gender, and a name that only exists for the other one would
-- spawn a zombie in nothing. an empty or throwing list is "cannot say", as above.
local function QSF_outfitExists(name, female)
    local ok, list = pcall(function() return getAllOutfits(female) end)
    if not ok or not list or list:size() == 0 then return true end
    return list:contains(name)
end

-- djb2 over the objective descriptors, to notice a reorder or retune that would leave
-- stored progress lined up against the wrong ordinals.
function QSF_Schema.signature(def)
    local parts = {}
    for i, obj in ipairs(def.objectives or {}) do
        local loc = obj.location
        if type(loc) == "table" then loc = "box" end
        parts[i] = table.concat({ obj.type, tostring(obj.item), tostring(obj.count), tostring(loc) }, "|")
    end

    local text = table.concat(parts, ";")
    local hash = 5381
    for i = 1, #text do
        hash = (hash * 33 + string.byte(text, i)) % 0x7FFFFFFF
    end
    return string.format("%x", hash)
end

-- a name, false for anywhere, a box, a radius, or a union. returns value plus an error.
local function QSF_normaliseLocation(loc, where)
    if loc == nil then return nil, nil end
    if loc == false then return false, nil end

    if type(loc) == "string" then
        if loc == "" then return nil, where .. ": location is an empty string" end
        return loc, nil
    end

    if type(loc) ~= "table" then
        return nil, where .. ": location must be a name, false, or a box"
    end

    if loc.any then
        if type(loc.any) ~= "table" or #loc.any == 0 then
            return nil, where .. ": location.any must be a non-empty list"
        end
        local out = {}
        for i, entry in ipairs(loc.any) do
            local cleaned, err = QSF_normaliseLocation(entry, where .. " any[" .. i .. "]")
            if err then return nil, err end
            out[i] = cleaned
        end
        return { any = out }, nil
    end

    if type(loc.x) ~= "number" or type(loc.y) ~= "number" then
        return nil, where .. ": location box needs numeric x and y"
    end

    if type(loc.radius) == "number" then
        if loc.radius <= 0 then return nil, where .. ": location radius must be above zero" end
        return { x = loc.x, y = loc.y, radius = loc.radius, z = loc.z }, nil
    end

    -- both spellings read naturally, so take either.
    local w = loc.w or loc.width
    local h = loc.h or loc.height
    if type(w) ~= "number" or type(h) ~= "number" or w <= 0 or h <= 0 then
        return nil, where .. ": location box needs a positive width and height, or a radius"
    end

    return { x = loc.x, y = loc.y, w = w, h = h, z = loc.z }, nil
end

-- a destination, not a region. a location can be a zone name or a union, neither of which
-- has a point to stand on, so where to put the player is written out separately.
local function QSF_normaliseTeleport(raw, key, errors)
    if raw == nil then return nil end

    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": teleport must be an object with x and y"
        return nil
    end

    if type(raw.x) ~= "number" or type(raw.y) ~= "number" then
        errors[#errors + 1] = key .. ": teleport needs numeric x and y"
        return nil
    end

    -- a location leaves z absent to mean any floor. somewhere to stand has to pick one.
    local z = tonumber(raw.z) or 0

    -- zero is no limit, the same as it means on repeatable.
    local cooldown = tonumber(raw.cooldownHours) or 0
    if cooldown < 0 then
        errors[#errors + 1] = key .. ": teleport cooldownHours cannot be negative"
        cooldown = 0
    end

    return {
        x = raw.x,
        y = raw.y,
        z = math.floor(z),
        cooldownHours = math.floor(cooldown),
    }
end

local function QSF_normaliseObjective(raw, index, questLocation, errors, key)
    local where = key .. " objective " .. index

    if type(raw) ~= "table" then
        errors[#errors + 1] = where .. ": not an object"
        return nil
    end

    local kind = raw.type
    if kind ~= "kill" and kind ~= "collect" then
        errors[#errors + 1] = where .. ": type must be kill or collect"
        return nil
    end

    local count = tonumber(raw.count)
    if not count or count < 1 then
        errors[#errors + 1] = where .. ": count must be a positive number"
        return nil
    end

    local location, locErr = QSF_normaliseLocation(raw.location, where)
    if locErr then
        errors[#errors + 1] = locErr
        return nil
    end

    -- absent inherits the quest's, false clears it. json cannot say "absent" any other way.
    if raw.location == nil then
        location = questLocation
    elseif location == false then
        location = nil
    end

    local obj = {
        type = kind,
        count = math.floor(count),
        location = location,
        label = raw.label,
    }

    if kind == "collect" then
        if type(raw.item) ~= "string" or raw.item == "" then
            errors[#errors + 1] = where .. ": collect needs an item full type such as Base.Nails"
            return nil
        end
        if not QSF_itemExists(raw.item) then
            errors[#errors + 1] = where .. ": unknown item " .. raw.item
            return nil
        end
        obj.item = raw.item
        obj.consume = raw.consume ~= false
    end

    return obj
end

local function QSF_normalisePrereqs(raw, errors, key)
    if raw == nil then return {} end
    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": prereqs must be an object"
        return {}
    end

    local out = { hidden = raw.hidden == true }

    if raw.quests ~= nil then
        if type(raw.quests) ~= "table" then
            errors[#errors + 1] = key .. ": prereqs.quests must be a list of quest keys"
        else
            out.quests = {}
            for _, questKey in ipairs(raw.quests) do
                if type(questKey) == "string" then
                    out.quests[#out.quests + 1] = questKey
                else
                    errors[#errors + 1] = key .. ": prereqs.quests holds a non-string entry"
                end
            end
        end
    end

    if raw.skills ~= nil then
        if type(raw.skills) ~= "table" then
            errors[#errors + 1] = key .. ": prereqs.skills must be an object of perk to level"
        else
            out.skills = {}
            for perkName, level in pairs(raw.skills) do
                local perk, unavailable = QSF_perkFromName(perkName)
                if not perk and not unavailable then
                    -- an admin writing Carpentry has no way to guess it is Woodwork.
                    errors[#errors + 1] = key .. ": unknown perk " .. tostring(perkName)
                        .. " (Carpentry is Woodwork, Foraging is PlantScavenging, First Aid is Doctor)"
                elseif type(level) ~= "number" then
                    errors[#errors + 1] = key .. ": prereqs.skills." .. tostring(perkName) .. " must be a number"
                else
                    out.skills[perkName] = math.floor(level)
                end
            end
        end
    end

    if raw.kills ~= nil then
        local n = tonumber(raw.kills)
        if n then out.kills = math.floor(n)
        else errors[#errors + 1] = key .. ": prereqs.kills must be a number" end
    end

    if raw.daysSurvived ~= nil then
        local n = tonumber(raw.daysSurvived)
        if n then out.daysSurvived = math.floor(n)
        else errors[#errors + 1] = key .. ": prereqs.daysSurvived must be a number" end
    end

    return out
end

-- shared by rewards.items and by every option in a reward choice, so a pool entry is held
-- to exactly the same standard as a flat reward. returns nil on anything unusable.
local function QSF_normaliseRewardItem(entry, where, errors)
    if type(entry) ~= "table" or type(entry.item) ~= "string" then
        errors[#errors + 1] = where .. " needs an item full type"
        return nil
    end

    if not QSF_itemExists(entry.item) then
        errors[#errors + 1] = where .. ": unknown item " .. entry.item
        return nil
    end

    local count = math.floor(tonumber(entry.count) or 1)
    if count < 1 then count = 1 end

    return { item = entry.item, count = count }
end

-- a pool the player picks one of at turn-in. a bad option is dropped and the rest still
-- stand; losing every one of them drops the choice rather than leaving an empty pool for
-- the picker to open on.
local function QSF_normaliseChoice(raw, errors, key)
    if raw == nil then return nil end

    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": rewards.choice must be an object with an options list"
        return nil
    end

    if type(raw.options) ~= "table" or #raw.options == 0 then
        errors[#errors + 1] = key .. ": rewards.choice needs a non-empty options list"
        return nil
    end

    local options = {}
    for i, entry in ipairs(raw.options) do
        local option = QSF_normaliseRewardItem(entry, key .. ": rewards.choice option " .. i, errors)
        if option then options[#options + 1] = option end
    end

    if #options == 0 then
        errors[#errors + 1] = key .. ": rewards.choice had no usable options, so it was dropped"
        return nil
    end

    if #options > MAX_CHOICE_OPTIONS then
        errors[#errors + 1] = key .. ": more than " .. MAX_CHOICE_OPTIONS .. " reward options makes an unwieldy picker"
    end

    return {
        label = (type(raw.label) == "string" and raw.label ~= "") and raw.label or nil,
        options = options,
    }
end

local function QSF_normaliseRewards(raw, errors, key)
    if raw == nil then return { items = {} } end
    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": rewards must be an object"
        return { items = {} }
    end

    local out = { items = {} }

    for i, entry in ipairs(raw.items or {}) do
        local item = QSF_normaliseRewardItem(entry, key .. ": reward item " .. i, errors)
        if item then out.items[#out.items + 1] = item end
    end

    if raw.xp ~= nil then
        if type(raw.xp) ~= "table" then
            errors[#errors + 1] = key .. ": rewards.xp must be an object of perk to amount"
        else
            out.xp = {}
            for perkName, amount in pairs(raw.xp) do
                local perk, unavailable = QSF_perkFromName(perkName)
                if not perk and not unavailable then
                    errors[#errors + 1] = key .. ": unknown perk in rewards.xp: " .. tostring(perkName)
                elseif type(amount) ~= "number" then
                    errors[#errors + 1] = key .. ": rewards.xp." .. tostring(perkName) .. " must be a number"
                else
                    out.xp[perkName] = amount
                end
            end
        end
    end

    out.choice = QSF_normaliseChoice(raw.choice, errors, key)

    return out
end

local function QSF_normaliseRepeatable(raw, errors, key)
    if raw == nil or raw == false then return nil end
    if raw == true then return { cooldownHours = 0, maxTurnins = 0 } end

    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": repeatable must be true, false, or an object"
        return nil
    end

    -- zero is no limit in both, so absent and explicitly-unlimited share a shape.
    return {
        cooldownHours = math.max(0, tonumber(raw.cooldownHours) or 0),
        maxTurnins = math.max(0, math.floor(tonumber(raw.maxTurnins) or 0)),
    }
end

-- what the giver says. every line is optional and the client has a stock one for each,
-- so a quest can name a giver and write nothing else.
local function QSF_normaliseDialogue(raw, errors, key)
    if raw == nil then return nil end

    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": dialogue must be an object of offer, progress and complete"
        return nil
    end

    local out = {}
    for _, field in ipairs({ "offer", "progress", "complete" }) do
        local line = raw[field]
        if type(line) == "string" and line ~= "" then
            out[field] = line
            QSF_checkPlaceholders(line, key, errors)
        elseif line ~= nil then
            errors[#errors + 1] = key .. ": dialogue." .. field .. " must be text"
        end
    end

    return out
end

-- returns def, errors. def is nil when the quest could not be salvaged at all.
function QSF_Schema.normalise(raw, sourceFile)
    local errors = {}

    if type(raw) ~= "table" then
        return nil, { (sourceFile or "?") .. ": quest entry is not an object" }
    end

    local key = raw.key
    if type(key) ~= "string" or not key:match(VALID_KEY) then
        return nil, { (sourceFile or "?") .. ": every quest needs a key of letters, digits, dot, dash or underscore" }
    end

    if type(raw.title) ~= "string" or raw.title == "" then
        return nil, { key .. ": needs a title" }
    end

    local questLocation, locErr = QSF_normaliseLocation(raw.location, key)
    if locErr then
        errors[#errors + 1] = locErr
        questLocation = nil
    end
    if questLocation == false then questLocation = nil end

    if type(raw.objectives) ~= "table" or #raw.objectives == 0 then
        return nil, { key .. ": needs at least one objective" }
    end

    local objectives = {}
    for i, rawObj in ipairs(raw.objectives) do
        local obj = QSF_normaliseObjective(rawObj, i, questLocation, errors, key)
        -- dropping one would renumber every later ordinal, and progress is keyed on those.
        if not obj then
            return nil, errors
        end
        objectives[i] = obj
    end

    local collectTypes = 0
    local consumes = false
    for _, obj in ipairs(objectives) do
        if obj.type == "collect" then
            collectTypes = collectTypes + 1
            if obj.consume then consumes = true end
        end
    end
    if collectTypes > MAX_COLLECT_TYPES then
        errors[#errors + 1] = key .. ": more than " .. MAX_COLLECT_TYPES .. " collect objectives will poll slowly"
    end

    local def = {
        key = key,
        title = raw.title,
        description = type(raw.description) == "string" and raw.description or "",
        order = tonumber(raw.order) or 100,
        location = questLocation,
        teleport = QSF_normaliseTeleport(raw.teleport, key, errors),
        prereqs = QSF_normalisePrereqs(raw.prereqs, errors, key),
        objectives = objectives,
        rewards = QSF_normaliseRewards(raw.rewards, errors, key),
        repeatable = QSF_normaliseRepeatable(raw.repeatable, errors, key),
        autoComplete = raw.autoComplete ~= false,
        giver = (type(raw.giver) == "string" and raw.giver ~= "") and raw.giver or nil,
        dialogue = QSF_normaliseDialogue(raw.dialogue, errors, key),
        source = sourceFile,
    }

    if raw.giver ~= nil and not def.giver then
        errors[#errors + 1] = key .. ": giver must be the key of an npc"
    end

    QSF_checkPlaceholders(def.description, key, errors)

    -- handing it in is something that happens at the giver, and the sweep would pay it
    -- out wherever the player happened to be. first, and silently: unlike the two below
    -- this is not a mistake an author made, and it leaves them nothing to report.
    if def.giver then def.autoComplete = false end

    -- otherwise the items go the instant the last one is picked up, with no prompt.
    if consumes and def.autoComplete then
        def.autoComplete = false
        errors[#errors + 1] = key .. ": has consuming collect objectives, so autoComplete was forced off"
    end

    -- there is nobody to ask which reward they wanted when the sweep fires the claim.
    if def.rewards.choice and def.autoComplete then
        def.autoComplete = false
        errors[#errors + 1] = key .. ": has a reward choice, so autoComplete was forced off"
    end

    def.sig = QSF_Schema.signature(def)
    return def, errors
end

-- returns npc, errors. npc is nil when there is no telling who it is or where it stands.
function QSF_Schema.normaliseNpc(raw, sourceFile)
    local errors = {}

    if type(raw) ~= "table" then
        return nil, { (sourceFile or "?") .. ": npc entry is not an object" }
    end

    local key = raw.key
    if type(key) ~= "string" or not key:match(VALID_KEY) then
        return nil, { (sourceFile or "?") .. ": every npc needs a key of letters, digits, dot, dash or underscore" }
    end

    local where = "npc " .. key

    if type(raw.x) ~= "number" or type(raw.y) ~= "number" then
        return nil, { where .. ": needs numeric x and y" }
    end

    local female = raw.female == true

    local outfit = raw.outfit
    if type(outfit) ~= "string" or outfit == "" then
        outfit = FALLBACK_OUTFIT
    elseif not QSF_outfitExists(outfit, female) then
        errors[#errors + 1] = where .. ": there is no " .. (female and "female" or "male")
            .. " outfit called " .. outfit .. ", so " .. FALLBACK_OUTFIT .. " is used"
        outfit = FALLBACK_OUTFIT
    end

    local skin = math.floor(tonumber(raw.skin) or 1)
    if skin < 1 or skin > 5 then
        errors[#errors + 1] = where .. ": skin must be 1 to 5"
        skin = 1
    end

    local facing = raw.facing
    if facing ~= nil and not FACINGS[facing] then
        errors[#errors + 1] = where .. ": facing must be one of N, NE, E, SE, S, SW, W, NW"
        facing = nil
    end

    QSF_checkPlaceholders(raw.greeting, where, errors)

    return {
        key = key,
        name = (type(raw.name) == "string" and raw.name ~= "") and raw.name or key,
        x = math.floor(raw.x),
        y = math.floor(raw.y),
        z = math.floor(tonumber(raw.z) or 0),
        outfit = outfit,
        female = female,
        skin = skin,
        -- south-east is toward the camera, so a face rather than the back of a head.
        facing = facing or "SE",
        greeting = (type(raw.greeting) == "string" and raw.greeting ~= "") and raw.greeting or nil,
        source = sourceFile,
    }, errors
end

-- the mistakes invisible in a single file: a prereq naming a quest nobody defined, a
-- prereq cycle, and a giver nobody defined.
function QSF_Schema.crossValidate(defs, npcs)
    local errors = {}

    -- a giver quest is kept off the log, so one pointing at nobody could never be taken.
    -- dropping the giver puts it back in the log, which is at least somewhere.
    for key, def in pairs(defs) do
        if def.giver and not (npcs and npcs[def.giver]) then
            errors[#errors + 1] = key .. ": giver " .. def.giver
                .. " is not a defined npc, so the quest is offered in the log instead"
            def.giver = nil
        end
    end

    for key, def in pairs(defs) do
        for _, needed in ipairs(def.prereqs.quests or {}) do
            if not defs[needed] then
                errors[#errors + 1] = key .. ": requires unknown quest " .. needed
            end
        end
    end

    -- a cycle leaves every quest in it permanently unavailable with no visible symptom.
    local UNVISITED, OPEN, CLOSED = 0, 1, 2
    local mark = {}
    for key in pairs(defs) do mark[key] = UNVISITED end

    local function walk(key, trail)
        if mark[key] == CLOSED then return end
        if mark[key] == OPEN then
            errors[#errors + 1] = "prereq cycle: " .. table.concat(trail, " -> ") .. " -> " .. key
            return
        end

        mark[key] = OPEN
        trail[#trail + 1] = key
        for _, needed in ipairs(defs[key] and defs[key].prereqs.quests or {}) do
            if defs[needed] then walk(needed, trail) end
        end
        trail[#trail] = nil
        mark[key] = CLOSED
    end

    for key in pairs(defs) do walk(key, {}) end

    return errors
end
