----------
--ESTRAL--
----------

require "QSF_Core"

QSF = QSF or {}
QSF_Schema = QSF_Schema or {}

local VALID_KEY = "^[%w_%.%-]+$"
local MAX_COLLECT_TYPES = 16

-- a lookup that throws means the engine is not ready yet, which is "cannot say" rather
-- than "invalid" - otherwise an early load would silently delete every objective.
local function QSF_itemExists(fullType)
    local ok, item = pcall(function() return getScriptManager():FindItem(fullType) end)
    if not ok then return true end
    return item ~= nil
end

local function QSF_perkFromName(name)
    local ok, perk = pcall(function() return PerkFactory.Perks.FromString(name) end)
    if not ok then return nil, true end
    return perk, false
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

local function QSF_normaliseRewards(raw, errors, key)
    if raw == nil then return { items = {} } end
    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": rewards must be an object"
        return { items = {} }
    end

    local out = { items = {} }

    for _, entry in ipairs(raw.items or {}) do
        if type(entry) ~= "table" or type(entry.item) ~= "string" then
            errors[#errors + 1] = key .. ": every reward item needs an item full type"
        elseif not QSF_itemExists(entry.item) then
            errors[#errors + 1] = key .. ": unknown reward item " .. entry.item
        else
            local count = math.floor(tonumber(entry.count) or 1)
            if count < 1 then count = 1 end
            out.items[#out.items + 1] = { item = entry.item, count = count }
        end
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
        prereqs = QSF_normalisePrereqs(raw.prereqs, errors, key),
        objectives = objectives,
        rewards = QSF_normaliseRewards(raw.rewards, errors, key),
        repeatable = QSF_normaliseRepeatable(raw.repeatable, errors, key),
        autoComplete = raw.autoComplete ~= false,
        source = sourceFile,
    }

    -- otherwise the items go the instant the last one is picked up, with no prompt.
    if consumes and def.autoComplete then
        def.autoComplete = false
        errors[#errors + 1] = key .. ": has consuming collect objectives, so autoComplete was forced off"
    end

    def.sig = QSF_Schema.signature(def)
    return def, errors
end

-- the two mistakes invisible in a single file: a prereq naming a quest nobody defined,
-- and a prereq cycle.
function QSF_Schema.crossValidate(defs)
    local errors = {}

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
