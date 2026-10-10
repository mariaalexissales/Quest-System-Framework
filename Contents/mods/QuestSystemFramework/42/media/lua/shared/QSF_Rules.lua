----------
--ESTRAL--
----------

require "QSF_Core"

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

-- everything a quest asks of a player before it can be taken, in the order it is asked.
-- given a list, each one goes into it with whether it is met. given none, the first one
-- that is not met is the answer, as canAccept's reason and what goes with it.
local function QSF_requirements(def, player, state, list)
    local prereqs = def.prereqs or {}

    for _, needed in ipairs(prereqs.quests or {}) do
        local other = state and state[needed]
        local met = other ~= nil and other.status == "done"

        if list then
            list[#list + 1] = { reason = "NeedQuest", detail = needed, met = met }
        elseif not met then
            return "NeedQuest", needed
        end
    end

    -- the rest are about the character, and there is nothing to ask without one.
    if not player then return nil end

    local skills = list and {} or nil

    for perkName, level in pairs(prereqs.skills or {}) do
        local met = QSF_perkLevel(player, perkName) >= level

        if skills then
            skills[#skills + 1] = { reason = "NeedSkill", detail = perkName, extra = level, met = met }
        elseif not met then
            -- apart, so the client can swap in the name the character sheet uses.
            return "NeedSkill", perkName, level
        end
    end

    if skills then
        -- pairs() hands them over in any order, and a list that reshuffles reads as broken.
        table.sort(skills, function(a, b) return a.detail < b.detail end)
        for _, entry in ipairs(skills) do list[#list + 1] = entry end
    end

    if prereqs.kills then
        local met = player:getZombieKills() >= prereqs.kills

        if list then
            list[#list + 1] = { reason = "NeedKills", detail = prereqs.kills, met = met }
        elseif not met then
            return "NeedKills", prereqs.kills
        end
    end

    if prereqs.daysSurvived then
        local met = getGameTime():getDaysSurvived() >= prereqs.daysSurvived

        if list then
            list[#list + 1] = { reason = "NeedDays", detail = prereqs.daysSurvived, met = met }
        elseif not met then
            return "NeedDays", prereqs.daysSurvived
        end
    end

    return nil
end

-- what a quest asks for, each with whether this player has it: the list the details show
-- with a tick or a cross on every line. the same walk canAccept refuses by.
function QSF_Rules.prereqList(def, player, state)
    local list = {}
    if def then QSF_requirements(def, player, state, list) end
    return list
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

    local reason, detail, extra = QSF_requirements(def, player, state)
    if reason then return false, reason, detail, extra end

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

-- a global quest's counters are the server's, collect ones included: what has been handed
-- over, not what anybody is carrying. run is its record. returns have, need, satisfied.
function QSF_Rules.sharedProgress(obj, index, run)
    local need = obj.count

    local have = 0
    if run and run.prog then have = run.prog[index] or 0 end
    return have, need, have >= need
end

-- the three below are asked of a player's own quest and of a global one alike. progress is
-- whichever of the two above the quest keeps count with.
local function QSF_allMet(def, rec, progress, counts)
    if not def or not rec then return false end

    for i, obj in ipairs(def.objectives) do
        local _, _, satisfied = progress(obj, i, rec, counts)
        if not satisfied then return false end
    end

    return true
end

-- each objective weighs the same, so a quest is not dominated by its largest number.
local function QSF_fraction(def, rec, progress, counts)
    if not def or #def.objectives == 0 then return 0 end

    local total = 0
    for i, obj in ipairs(def.objectives) do
        local have, need = progress(obj, i, rec, counts)
        if need > 0 then
            total = total + math.min(1, have / need)
        end
    end

    return total / #def.objectives
end

-- what a row says beside a quest somebody is on: the counter itself when there is only
-- the one, and otherwise how many of them are met.
local function QSF_tally(def, rec, progress, counts)
    if #def.objectives == 1 then
        local have, need = progress(def.objectives[1], 1, rec, counts)
        return have .. "/" .. need
    end

    local done = 0
    for i, obj in ipairs(def.objectives) do
        local _, _, satisfied = progress(obj, i, rec, counts)
        if satisfied then done = done + 1 end
    end

    return done .. "/" .. #def.objectives
end

function QSF_Rules.isComplete(def, rec, counts)
    return QSF_allMet(def, rec, QSF_Rules.objectiveProgress, counts)
end

function QSF_Rules.overallProgress(def, rec, counts)
    return QSF_fraction(def, rec, QSF_Rules.objectiveProgress, counts)
end

function QSF_Rules.tally(def, rec, counts)
    return QSF_tally(def, rec, QSF_Rules.objectiveProgress, counts)
end

function QSF_Rules.sharedComplete(def, run)
    return QSF_allMet(def, run, QSF_Rules.sharedProgress)
end

function QSF_Rules.sharedOverall(def, run)
    return QSF_fraction(def, run, QSF_Rules.sharedProgress)
end

function QSF_Rules.sharedTally(def, run)
    return QSF_tally(def, run, QSF_Rules.sharedProgress)
end

-- one counter an objective, all at nothing. dense from 1: a hole in a kahlua array loses
-- everything after it.
function QSF_Rules.blankProgress(def)
    local prog = {}
    for i = 1, #def.objectives do prog[i] = 0 end
    return prog
end

-- by the order somebody gave them, then by key. pairs() alone would reshuffle the list
-- between openings, and hand every client a different one.
function QSF_Rules.sorted(defs)
    local ordered = {}
    for _, def in pairs(defs) do ordered[#ordered + 1] = def end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)

    return ordered
end

-- what one player could hand over right now: toward every collect objective still short,
-- as much as they hold and no more than is missing. the button is enabled with this and
-- the server takes with it. returns the total, and how many toward each objective.
function QSF_Rules.givable(def, run, counts)
    local total, plan = 0, {}
    if not def or not run or run.status ~= "active" then return total, plan end

    -- two objectives can ask for the same item, and it can only be handed over once.
    local held = {}

    for i, obj in ipairs(def.objectives) do
        if obj.type == "collect" then
            if held[obj.item] == nil then held[obj.item] = (counts and counts[obj.item]) or 0 end

            local have, need = QSF_Rules.sharedProgress(obj, i, run)
            local amount = math.min(held[obj.item], need - have)

            if amount > 0 then
                plan[i] = amount
                held[obj.item] = held[obj.item] - amount
                total = total + amount
            end
        end
    end

    return total, plan
end

-- a payout with nothing in it is not owed to anybody.
function QSF_Rules.hasRewards(rewards)
    if not rewards then return false end
    if rewards.items and #rewards.items > 0 then return true end
    return rewards.xp ~= nil and not table.isempty(rewards.xp)
end

-- the union across active quests, so the poll asks once per type not once per objective.
-- state is a player's own records or the global runs, which say "active" the same way,
-- and wanted is a set to add to when both are being asked about.
function QSF_Rules.wantedItems(defs, state, wanted)
    wanted = wanted or {}

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
