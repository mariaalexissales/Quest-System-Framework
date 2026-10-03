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

-- the engine's perk for a name out of a quest file, or nil. FromString never answers nil
-- itself: a name it does not know comes back as the MAX placeholder, which no character
-- has a level in.
function QSF_Rules.perk(name)
    local perk = PerkFactory.Perks.FromString(name)
    if not perk or perk == PerkFactory.Perks.MAX then return nil end
    return perk
end

local function QSF_perkLevel(player, perkName)
    local perk = QSF_Rules.perk(perkName)
    if not perk then return 0 end
    return player:getPerkLevel(perk)
end

-- an npc is a zombie underneath, and this is the one thing about a zombie that reaches
-- every client and survives a save. bit 15 only says the hat has come off, and would
-- otherwise make it somebody else the moment it did.
function QSF_Rules.npcId(zombie)
    local id = zombie:getPersistentOutfitID()
    if id % 65536 >= 32768 then id = id - 32768 end
    return id
end

-- the id is rolled per outfit, so any other zombie in the same clothes can turn up with
-- the same one. both sides only ever accept it this close to where the npc stands.
function QSF_Rules.isNear(x, y, z, npc, tiles)
    if not npc or not x or not y then return false end
    if math.floor(z or 0) ~= npc.z then return false end

    -- measured from the middle of the tile, which is where it is stood.
    local dx = x - (npc.x + 0.5)
    local dy = y - (npc.y + 0.5)
    return (dx * dx + dy * dy) <= (tiles * tiles)
end

function QSF_Rules.inReach(player, npc)
    if not player or not npc then return false end
    return QSF_Rules.isNear(player:getX(), player:getY(), player:getZ(), npc, QSF.NPC_REACH)
end

-- the same split as canAccept: the dialogue only offers a quest with this and the server
-- only takes or pays one with it. npcs is the table either side keeps, by key. a quest
-- with no giver is dealt with from the log, wherever the player is.
function QSF_Rules.atGiver(def, npcs, player)
    if not def or not def.giver then return true end
    return QSF_Rules.inReach(player, npcs and npcs[def.giver])
end

-- what one npc hands out, in the order the log would list it. ordered is the sorted quest
-- list either side already keeps.
function QSF_Rules.npcQuests(npcKey, ordered)
    local out = {}

    for _, def in ipairs(ordered or {}) do
        if def.giver == npcKey then out[#out + 1] = def end
    end

    return out
end

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
                -- apart, so the client can swap in the name the character sheet uses.
                return false, "NeedSkill", perkName, level
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

-- what a quest is to one player right now. the marker, the conversation and the log all
-- ask this one question, so they cannot each come to their own answer.
--   turnin     taken, and every objective met
--   progress   taken, and not there yet
--   available  can be taken now
--   done       finished, and not to be taken again, or not yet
--   hidden     locked, and not allowed to hint at itself
--   locked     locked
-- anything but the first three also returns what canAccept said was in the way.
function QSF_Rules.questState(def, rec, player, state, counts)
    if rec and rec.status == "active" then
        return QSF_Rules.isComplete(def, rec, counts) and "turnin" or "progress"
    end

    local ok, reason, detail, extra = QSF_Rules.canAccept(def, rec, player, state)
    if ok then return "available" end

    if rec and rec.status == "done" then return "done", reason, detail, extra end
    if def and def.prereqs and def.prereqs.hidden then return "hidden", reason, detail, extra end
    return "locked", reason, detail, extra
end

-- the same split as canAccept: the client greys the button with this and the server
-- authorises with it, so a greyed button and a refused command cannot disagree.
function QSF_Rules.canTeleport(def, rec)
    if not def or not def.teleport then return false, "NoTeleport" end

    -- the destination only exists for a quest somebody is actually on.
    if not rec or rec.status ~= "active" then return false, "NotActive" end

    local cooldown = def.teleport.cooldownHours or 0
    if cooldown > 0 and rec.tp then
        local readyAt = rec.tp + cooldown
        local now = QSF_worldHours()
        if now < readyAt then
            return false, "OnCooldown", math.ceil(readyAt - now)
        end
    end

    return true
end

-- the same split again: the panel enables Confirm with this and the server authorises the
-- payout with it, so a pick the picker allowed cannot be one the server refuses. the pick
-- is an ordinal into the server's own options, never an item name.
function QSF_Rules.pickedReward(def, pick)
    local choice = def and def.rewards and def.rewards.choice
    if not choice then return nil, "NoChoice" end

    local n = tonumber(pick)
    if not n or n ~= math.floor(n) then return nil, "NeedPick" end
    if n < 1 or n > #choice.options then return nil, "NeedPick" end

    return choice.options[n]
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
