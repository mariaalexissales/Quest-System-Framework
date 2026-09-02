----------
--ESTRAL--
----------

require "QSF_Core"

-- every question of the form "may this player do this yet" lives here, and both sides
-- call it. the client greys a row with these functions and the server authorises the
-- same action with the same functions, so the two cannot drift into disagreeing about
-- what is allowed - which is the bug that makes a quest log feel broken.

QSF = QSF or {}
QSF_Rules = QSF_Rules or {}

local function QSF_worldHours()
    local ok, hours = pcall(function() return getGameTime():getWorldAgeHours() end)
    if ok and hours then return hours end
    return 0
end

QSF_Rules.worldHours = QSF_worldHours

local function QSF_perkLevel(player, perkName)
    local ok, level = pcall(function()
        local perk = PerkFactory.Perks.FromString(perkName)
        if not perk then return 0 end
        return player:getPerkLevel(perk)
    end)
    if ok and level then return level end
    return 0
end

QSF_Rules.perkLevel = QSF_perkLevel

-- returns ok, reasonKey, detail. the reason is a translation key suffix so the ui can
-- say what is missing rather than just refusing.
function QSF_Rules.canAccept(def, rec, player, state)
    if not def then return false, "Unknown" end

    if rec and rec.status == "active" then
        return false, "AlreadyActive"
    end

    local turnins = rec and rec.turnins or 0

    if rec and rec.status == "done" then
        if not def.repeatable then
            return false, "AlreadyDone"
        end
        if def.repeatable.maxTurnins > 0 and turnins >= def.repeatable.maxTurnins then
            return false, "MaxTurnins"
        end
        if def.repeatable.cooldownHours > 0 then
            local readyAt = (rec.done or 0) + def.repeatable.cooldownHours
            local now = QSF_worldHours()
            if now < readyAt then
                return false, "OnCooldown", math.ceil(readyAt - now)
            end
        end
    end

    local prereqs = def.prereqs or {}

    for _, needed in ipairs(prereqs.quests or {}) do
        local other = state and state[needed]
        if not other or other.status ~= "done" then
            return false, "NeedQuest", needed
        end
    end

    if player then
        for perkName, level in pairs(prereqs.skills or {}) do
            if QSF_perkLevel(player, perkName) < level then
                return false, "NeedSkill", perkName .. " " .. level
            end
        end

        if prereqs.kills and player:getZombieKills() < prereqs.kills then
            return false, "NeedKills", prereqs.kills
        end

        if prereqs.daysSurvived then
            local ok, days = pcall(function() return getGameTime():getDaysSurvived() end)
            if ok and days and days < prereqs.daysSurvived then
                return false, "NeedDays", prereqs.daysSurvived
            end
        end
    end

    return true
end

-- counts is a map of item full type to how many the player holds, gathered by whoever is
-- asking. kill progress comes from the stored record. returns have, need, satisfied.
function QSF_Rules.objectiveProgress(obj, index, rec, counts)
    local need = obj.count

    if obj.type == "collect" then
        local have = (counts and counts[obj.item]) or 0
        return have, need, have >= need
    end

    local have = 0
    if rec and rec.prog then have = rec.prog[index] or 0 end
    return have, need, have >= need
end

function QSF_Rules.isComplete(def, rec, counts)
    if not def or not rec then return false end

    for i, obj in ipairs(def.objectives) do
        local _, _, satisfied = QSF_Rules.objectiveProgress(obj, i, rec, counts)
        if not satisfied then return false end
    end

    return true
end

-- the fraction across every objective, for the row's progress bar. each objective counts
-- equally regardless of its size, so a quest is not dominated by its largest number.
function QSF_Rules.overallProgress(def, rec, counts)
    if not def or #def.objectives == 0 then return 0 end

    local total = 0
    for i, obj in ipairs(def.objectives) do
        local have, need = QSF_Rules.objectiveProgress(obj, i, rec, counts)
        if need > 0 then
            total = total + math.min(1, have / need)
        end
    end

    return total / #def.objectives
end

-- the union of item types the player's active quests care about, so the inventory poll
-- asks the engine once per type instead of once per objective.
function QSF_Rules.wantedItems(defs, state)
    local wanted = {}

    for key, rec in pairs(state or {}) do
        if rec.status == "active" then
            local def = defs and defs[key]
            for _, obj in ipairs(def and def.objectives or {}) do
                if obj.type == "collect" then wanted[obj.item] = true end
            end
        end
    end

    return wanted
end
