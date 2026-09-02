----------
--ESTRAL--
----------

require "QSF_Core"

QSF = QSF or {}
QSF_Rules = QSF_Rules or {}

local function QSF_worldHours()
    return getGameTime():getWorldAgeHours()
end

QSF_Rules.worldHours = QSF_worldHours

local function QSF_perkLevel(player, perkName)
    local perk = PerkFactory.Perks.FromString(perkName)
    if not perk then return 0 end
    return player:getPerkLevel(perk)
end

QSF_Rules.perkLevel = QSF_perkLevel

-- the client greys a row with this and the server authorises with it, so a greyed row and
-- a refused button cannot disagree. reason is a translation key suffix.
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

        if prereqs.daysSurvived and getGameTime():getDaysSurvived() < prereqs.daysSurvived then
            return false, "NeedDays", prereqs.daysSurvived
        end
    end

    return true
end

-- counts maps item full type to how many the player holds; kill progress comes off the
-- stored record. returns have, need, satisfied.
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

-- each objective weighs the same, so a quest is not dominated by its largest number.
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

-- the union across active quests, so the poll asks once per type not once per objective.
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
