----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_Text"

QSF_Schema = QSF_Schema or {}

local VALID_KEY = "^[%w_%.%-]+$"
local MAX_COLLECT_TYPES = 16
local MAX_CHOICE_OPTIONS = 8

local FALLBACK_OUTFIT = "Generic01"
local FACINGS = { N = true, NE = true, E = true, SE = true, S = true, SW = true, W = true, NW = true }

-- text somebody actually wrote, or nil.
local function QSF_written(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- the form an admin places an npc with holds a key to the same thing.
function QSF_Schema.validKey(key)
    return type(key) == "string" and key:match(VALID_KEY) ~= nil
end

-- who an entry is. what is its name to whoever wrote the file, and prefix goes in front of
-- its key in everything said about it afterwards. returns that, or nil and the reason.
local function QSF_identify(raw, sourceFile, what, prefix)
    if type(raw) ~= "table" then
        return nil, { (sourceFile or "?") .. ": " .. what .. " entry is not an object" }
    end

    if not QSF_Schema.validKey(raw.key) then
        return nil, { (sourceFile or "?") .. ": every " .. what
            .. " needs a key of letters, digits, dot, dash or underscore" }
    end

    return prefix .. raw.key
end

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

-- counted by One More Horde, which says who survived and who killed but never where, so
-- these two carry no location at all.
local HORDE_TYPES = { horde = true, hordeKill = true }

local function QSF_normaliseObjective(raw, index, questLocation, errors, key)
    local where = key .. " objective " .. index

    if type(raw) ~= "table" then
        errors[#errors + 1] = where .. ": not an object"
        return nil
    end

    local kind = raw.type
    if kind ~= "kill" and kind ~= "collect" and not HORDE_TYPES[kind] then
        errors[#errors + 1] = where .. ": type must be kill, collect, horde or hordeKill"
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
    if HORDE_TYPES[kind] then
        location = nil
    elseif raw.location == nil then
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

-- an object of perk to number, which is both what a quest asks for and what it pays.
local SKILLS = {
    field = "prereqs.skills", holds = "level", whole = true,
    -- an admin writing Carpentry has no way to guess it is Woodwork.
    unknown = "unknown perk %s (Carpentry is Woodwork, Foraging is PlantScavenging, First Aid is Doctor)",
}
local XP = { field = "rewards.xp", holds = "amount", unknown = "unknown perk in rewards.xp: %s" }

-- nil when it is not an object at all, and otherwise whatever in it could be read.
local function QSF_normalisePerks(raw, errors, key, kind)
    if type(raw) ~= "table" then
        errors[#errors + 1] = key .. ": " .. kind.field .. " must be an object of perk to " .. kind.holds
        return nil
    end

    local out = {}
    for perkName, value in pairs(raw) do
        local perk, unavailable = QSF_perkFromName(perkName)
        if not perk and not unavailable then
            errors[#errors + 1] = key .. ": " .. string.format(kind.unknown, tostring(perkName))
        elseif type(value) ~= "number" then
            errors[#errors + 1] = key .. ": " .. kind.field .. "." .. tostring(perkName) .. " must be a number"
        else
            out[perkName] = kind.whole and math.floor(value) or value
        end
    end

    return out
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

    if raw.skills ~= nil then out.skills = QSF_normalisePerks(raw.skills, errors, key, SKILLS) end

    for _, field in ipairs({ "kills", "daysSurvived" }) do
        if raw[field] ~= nil then
            local n = tonumber(raw[field])
            if n then out[field] = math.floor(n)
            else errors[#errors + 1] = key .. ": prereqs." .. field .. " must be a number" end
        end
    end

    return out
end

-- shared by rewards.items and by every option in a reward pool, so a pool entry is held
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

-- a pool of rewards under rewards[field]. choice is the one the player picks from at
-- turn-in. a bad option is dropped and the rest still stand; losing every one of them drops
-- the pool rather than leaving an empty one for the picker to open on.
local function QSF_normalisePool(raw, errors, key, field)
    if raw == nil then return nil end

    local name = key .. ": rewards." .. field

    if type(raw) ~= "table" then
        errors[#errors + 1] = name .. " must be an object with an options list"
        return nil
    end

    if type(raw.options) ~= "table" or #raw.options == 0 then
        errors[#errors + 1] = name .. " needs a non-empty options list"
        return nil
    end

    local options = {}
    for i, entry in ipairs(raw.options) do
        local option = QSF_normaliseRewardItem(entry, name .. " option " .. i, errors)
        if option then options[#options + 1] = option end
    end

    if #options == 0 then
        errors[#errors + 1] = name .. " had no usable options, so it was dropped"
        return nil
    end

    if field == "choice" and #options > MAX_CHOICE_OPTIONS then
        errors[#errors + 1] = key .. ": more than " .. MAX_CHOICE_OPTIONS .. " reward options makes an unwieldy picker"
    end

    return { label = QSF_written(raw.label), options = options }
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

    if raw.xp ~= nil then out.xp = QSF_normalisePerks(raw.xp, errors, key, XP) end

    out.choice = QSF_normalisePool(raw.choice, errors, key, "choice")

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
        if QSF_written(line) then
            out[field] = line
            QSF_checkPlaceholders(line, key, errors)
        elseif line ~= nil then
            errors[#errors + 1] = key .. ": dialogue." .. field .. " must be text"
        end
    end

    return out
end

-- what a quest and a global quest have in common: who it is, where it is and what it asks
-- for. returns the start of a def, its errors so far and the name they are filed under, or
-- nil and why there was nothing to salvage.
local function QSF_normaliseBase(raw, sourceFile, what, prefix)
    local where, fatal = QSF_identify(raw, sourceFile, what, prefix)
    if not where then return nil, fatal end

    if type(raw.title) ~= "string" or raw.title == "" then
        return nil, { where .. ": needs a title" }
    end

    local errors = {}

    local questLocation, locErr = QSF_normaliseLocation(raw.location, where)
    if locErr then
        errors[#errors + 1] = locErr
        questLocation = nil
    end
    if questLocation == false then questLocation = nil end

    if type(raw.objectives) ~= "table" or #raw.objectives == 0 then
        return nil, { where .. ": needs at least one objective" }
    end

    local objectives = {}
    for i, rawObj in ipairs(raw.objectives) do
        local obj = QSF_normaliseObjective(rawObj, i, questLocation, errors, where)
        -- dropping one would renumber every later ordinal, and progress is keyed on those,
        -- a player's own and the shared counters alike.
        if not obj then
            return nil, errors
        end
        objectives[i] = obj
    end

    local def = {
        key = raw.key,
        title = raw.title,
        description = type(raw.description) == "string" and raw.description or "",
        order = tonumber(raw.order) or 100,
        location = questLocation,
        objectives = objectives,
        source = sourceFile,
    }

    return def, errors, where
end

-- returns def, errors. def is nil when the quest could not be salvaged at all.
function QSF_Schema.normalise(raw, sourceFile)
    local def, errors, key = QSF_normaliseBase(raw, sourceFile, "quest", "")
    if not def then return nil, errors end

    local collectTypes = 0
    local consumes = false
    for _, obj in ipairs(def.objectives) do
        if obj.type == "collect" then
            collectTypes = collectTypes + 1
            if obj.consume then consumes = true end
        end
    end
    if collectTypes > MAX_COLLECT_TYPES then
        errors[#errors + 1] = key .. ": more than " .. MAX_COLLECT_TYPES .. " collect objectives will poll slowly"
    end

    def.teleport = QSF_normaliseTeleport(raw.teleport, key, errors)
    def.prereqs = QSF_normalisePrereqs(raw.prereqs, errors, key)
    def.rewards = QSF_normaliseRewards(raw.rewards, errors, key)
    def.repeatable = QSF_normaliseRepeatable(raw.repeatable, errors, key)
    def.autoComplete = raw.autoComplete ~= false
    def.giver = QSF_written(raw.giver)
    def.dialogue = QSF_normaliseDialogue(raw.dialogue, errors, key)

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

local STARTS = { auto = true, manual = true }

-- held to the same standard as a quest's rewards, less the one thing nobody is there to
-- answer: these are paid when the quest ends, to people who may not even be online.
local function QSF_normalisePayout(raw, errors, where)
    local out = QSF_normaliseRewards(raw, errors, where)

    if out.choice then
        out.choice = nil
        errors[#errors + 1] = where .. ": a global quest pays everybody the same, so the choice was dropped"
    end

    return out
end

-- a quest the whole server works on. returns def, errors, the same as normalise.
function QSF_Schema.normaliseGlobal(raw, sourceFile)
    local def, errors, where = QSF_normaliseBase(raw, sourceFile, "global quest", "global ")
    if not def then return nil, errors end

    -- handed over from the log, wherever the player is, and always for keeps.
    for _, obj in ipairs(def.objectives) do
        if obj.type == "collect" then
            obj.location = nil
            obj.consume = true
        end
    end

    local start = raw.start
    if start == nil then
        start = "manual"
    elseif not STARTS[start] then
        errors[#errors + 1] = where .. ": start must be auto or manual, so it waits for an admin"
        start = "manual"
    end

    -- zero is no time limit, the same as it means everywhere else. real hours, not the
    -- world's: an event ends when the server owner said it would, however much anyone slept.
    local duration = tonumber(raw.durationHours) or 0
    if duration < 0 then
        errors[#errors + 1] = where .. ": durationHours cannot be negative"
        duration = 0
    end

    def.rewards = QSF_normalisePayout(raw.rewards, errors, where)
    def.consolation = raw.consolation ~= nil
        and QSF_normalisePayout(raw.consolation, errors, where .. " consolation") or nil
    def.start = start
    def.durationHours = duration
    def.minContribution = math.max(1, math.floor(tonumber(raw.minContribution) or 1))

    QSF_checkPlaceholders(def.description, where, errors)

    def.sig = QSF_Schema.signature(def)
    return def, errors
end

-- returns npc, errors. npc is nil when there is no telling who it is or where it stands.
function QSF_Schema.normaliseNpc(raw, sourceFile)
    local where, fatal = QSF_identify(raw, sourceFile, "npc", "npc ")
    if not where then return nil, fatal end

    if type(raw.x) ~= "number" or type(raw.y) ~= "number" then
        return nil, { where .. ": needs numeric x and y" }
    end

    local errors = {}
    local female = raw.female == true

    local outfit = QSF_written(raw.outfit)
    if not outfit then
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
        key = raw.key,
        name = QSF_written(raw.name) or raw.key,
        x = math.floor(raw.x),
        y = math.floor(raw.y),
        z = math.floor(tonumber(raw.z) or 0),
        outfit = outfit,
        female = female,
        skin = skin,
        -- south-east is toward the camera, so a face rather than the back of a head.
        facing = facing or "SE",
        greeting = QSF_written(raw.greeting),
        source = sourceFile,
    }, errors
end

local function QSF_warnHorde(defs, prefix, errors)
    for key, def in pairs(defs) do
        for _, obj in ipairs(def.objectives) do
            if HORDE_TYPES[obj.type] then
                errors[#errors + 1] = prefix .. key .. ": " .. obj.type
                    .. " objectives need One More Horde, and will not move without it"
                break
            end
        end
    end
end

-- the mistakes invisible in a single file: a prereq naming a quest nobody defined, a
-- prereq cycle, and a giver nobody defined.
function QSF_Schema.crossValidate(defs, npcs, globals)
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

    -- kept rather than rejected: the same file has to load on a server that adds the mod
    -- later. looked up at call time, and nil when One More Horde is off.
    if not OneMoreHordeExtensions then
        QSF_warnHorde(defs, "", errors)
        QSF_warnHorde(globals or {}, "global ", errors)
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
