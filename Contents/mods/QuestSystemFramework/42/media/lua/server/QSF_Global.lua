----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Location"
require "QSF_Net"
require "QSF_Rules"
require "QSF_Defs"
require "QSF_Bridge"
require "QSF_State"
require "QSF_Rewards"
require "QSF_Verify"

if not QSF.isAuthority() then return end

QSF_Global = QSF_Global or {}

local TABLE_NAME = "QSF_Global"
local FLUSH_MS = 2000
local HOUR_MS = 3600000

QSF_Global.data = QSF_Global.data or nil
QSF_Global.ready = QSF_Global.ready or false

-- runtime only: which quests have moved since everybody was last told, and for whom.
QSF_Global.dirty = QSF_Global.dirty or {}
QSF_Global.lastFlush = QSF_Global.lastFlush or 0

-- runs is one record per quest key, the latest time it ran. owed is every payout somebody
-- has not had yet, each with the reward as it stood when the quest ended, so it is still
-- payable after the quest has been edited, restarted or taken out of the files.
function QSF_Global.ensure()
    if not QSF_Global.data then
        QSF_Global.data = ModData.getOrCreate(TABLE_NAME)
    end

    local data = QSF_Global.data
    if not data.runs then data.runs = {} end
    if not data.owed then data.owed = {} end
    data.v = QSF.SCHEMA_V

    return data
end

-- what a client is told about one run. two machines' clocks do not agree, so the end
-- travels as how long is left and each client pins that to its own. what one player put
-- in is only there when the packet is theirs alone.
local function QSF_wireRun(run, username)
    local left = nil
    if run.status == "active" and run.ends then
        left = math.max(0, run.ends - getTimestampMs())
    end

    return {
        status = run.status,
        run = run.run,
        prog = run.prog,
        count = run.count or 0,
        left = left,
        mine = username and (run.players[username] or 0) or nil,
    }
end

function QSF_Global.sendSnapshot(player)
    if not player then return end

    local username = player:getUsername()
    local runs = {}

    for key, run in pairs(QSF_Global.ensure().runs) do
        runs[key] = QSF_wireRun(run, username)
    end

    QSF_Net.toClient(player, "gstate", { runs = runs })
end

-- the shared half goes to everybody in one packet. who is the names whose own number
-- moved, and each of those is told theirs separately.
function QSF_Global.broadcast(key, who)
    local run = QSF_Global.ensure().runs[key]
    if not run then return end

    QSF_Net.toAll("gdelta", { key = key, run = QSF_wireRun(run) })

    for username in pairs(who or {}) do
        local player = QSF_State.playerByName(username)
        if player then
            QSF_Net.toClient(player, "gmine", { key = key, mine = run.players[username] or 0 })
        end
    end
end

function QSF_Global.flush()
    for key, who in pairs(QSF_Global.dirty) do
        QSF_Global.broadcast(key, who)
    end

    QSF_Global.dirty = {}
    QSF_Global.lastFlush = getTimestampMs()
end

function QSF_Global.start(key)
    local def = QSF_Defs.global[key]
    if not def then return false, "Unknown" end

    local data = QSF_Global.ensure()
    local last = data.runs[key]
    if last and last.status == "active" then return false, "AlreadyActive" end

    local now = getTimestampMs()

    local run = {
        status = "active",
        run = (last and last.run or 0) + 1,
        sig = def.sig,
        started = now,
        ends = def.durationHours > 0 and (now + def.durationHours * HOUR_MS) or nil,
        prog = QSF_Rules.blankProgress(def),
        players = {},
        count = 0,
    }

    data.runs[key] = run

    QSF.log("global quest " .. key .. " started, run " .. run.run)

    QSF_Global.broadcast(key)
    QSF_Net.toAll("toast", { kind = "globalStarted", title = def.title })
    QSF_Bridge.emit("globalStarted", { key = key, title = def.title, run = run.run,
        ends = QSF_Bridge.seconds(run.ends) })

    return true
end

-- everything this player is owed, from however many quests ended while they were away.
function QSF_Global.settle(player)
    if not player then return end

    local username = player:getUsername()
    if not username then return end

    -- it would go into a corpse. the next character says hello and is paid then.
    if player:isDead() then return end

    local data = QSF_Global.ensure()
    local kept = {}

    for _, entry in ipairs(data.owed) do
        if entry.to[username] then
            -- struck off first, so a payout that throws partway is short once rather
            -- than paid again on every login.
            entry.to[username] = nil

            local rolled = QSF_Rewards.grant(player, { key = entry.key, rewards = entry.rewards })
            QSF_Net.toClient(player, "toast", { kind = "globalPaid", title = entry.title, outcome = entry.outcome,
                rolled = rolled })

            QSF.log(username .. " paid for global quest " .. entry.key .. " (" .. entry.outcome .. ")")
            QSF_Bridge.emit("globalPaid", { username = username, key = entry.key, title = entry.title,
                run = entry.run, outcome = entry.outcome, rolled = rolled })
        end

        if not table.isempty(entry.to) then kept[#kept + 1] = entry end
    end

    data.owed = kept
end

-- completed pays the reward and expired pays the consolation. everybody who put in
-- enough is owed it from this moment, and whoever is here is paid on the spot.
function QSF_Global.finish(key, outcome)
    local data = QSF_Global.ensure()
    local run = data.runs[key]
    if not run or run.status ~= "active" then return false end

    run.status = outcome
    run.ended = getTimestampMs()

    local def = QSF_Defs.global[key]
    local title = def and def.title or key
    local rewards = nil

    if def then
        rewards = outcome == "completed" and def.rewards or def.consolation
    else
        QSF.warn("global quest " .. key .. " ended after it was taken out of the files, so nobody is paid")
    end

    local owed = 0

    if QSF_Rules.hasRewards(rewards) then
        local to = {}

        for username, units in pairs(run.players) do
            if units >= def.minContribution then
                to[username] = true
                owed = owed + 1
            end
        end

        if owed > 0 then
            data.owed[#data.owed + 1] = {
                key = key,
                run = run.run,
                title = title,
                outcome = outcome,
                rewards = rewards,
                to = to,
            }
        end
    end

    QSF.log("global quest " .. key .. " " .. outcome .. ": " .. (run.count or 0)
        .. " took part, " .. owed .. " to be paid")

    QSF_Global.dirty[key] = nil
    QSF_Global.broadcast(key)
    QSF_Net.toAll("toast", { kind = outcome == "completed" and "globalCompleted" or "globalExpired", title = title })

    for _, player in ipairs(QSF_State.players()) do
        QSF_Global.settle(player)
    end

    -- after the settling, so whoever hears it is told who is still waiting to be paid.
    QSF_Bridge.emit("globalEnded", { key = key, title = title, run = run.run, outcome = outcome,
        participants = run.count or 0, owed = owed })

    return true
end

-- capped the way a personal counter is. returns how much of it counted.
local function QSF_add(run, index, cap, username, amount)
    local have = run.prog[index] or 0
    local counted = math.min(amount, cap - have)
    if counted <= 0 then return 0 end

    run.prog[index] = have + counted

    if not run.players[username] then
        run.players[username] = 0
        run.count = (run.count or 0) + 1
    end

    run.players[username] = run.players[username] + counted

    return counted
end

-- after anything that moved a counter: finish the quest if that was the last of it,
-- otherwise say so, held back so a horde is not one packet per kill. urgent skips that.
local function QSF_moved(key, username, urgent)
    local run = QSF_Global.ensure().runs[key]

    if QSF_Rules.sharedComplete(QSF_Defs.global[key], run) then
        QSF_Global.finish(key, "completed")
        return
    end

    QSF_Global.dirty[key] = QSF_Global.dirty[key] or {}
    QSF_Global.dirty[key][username] = true

    if urgent or (getTimestampMs() - QSF_Global.lastFlush) >= FLUSH_MS then
        QSF_Global.flush()
    end
end

-- one step on every running quest's objectives of this kind. QSF_Kills.bump calls it with
-- whatever it was given, so kills and both horde counts arrive through the one door.
function QSF_Global.bump(username, kind, x, y, z, seen)
    if not username or not QSF_Global.ready then return end

    for key, run in pairs(QSF_Global.ensure().runs) do
        local def = run.status == "active" and QSF_Defs.global[key] or nil

        if def then
            local counted = 0

            for i, obj in ipairs(def.objectives) do
                if QSF_Location.takes(obj, kind, x, y, z, seen) then
                    counted = counted + QSF_add(run, i, obj.count, username, 1)
                end
            end

            if counted > 0 then QSF_moved(key, username) end
        end
    end
end

-- everything the player holds toward every collect objective still short, and never more
-- than is missing. counted on the server's own copy of their inventory. returns how many
-- items went, or nil and why not.
function QSF_Global.give(player, key)
    local def = QSF_Defs.global[key]
    local run = QSF_Global.ensure().runs[key]
    if not def or not run or run.status ~= "active" then return nil, "NotRunning" end

    local total, plan = QSF_Rules.givable(def, run, QSF_Verify.countItems(player, def))
    if total == 0 then return nil, "NothingToGive" end

    local username = player:getUsername()
    local given = 0

    for i, obj in ipairs(def.objectives) do
        if plan[i] then
            -- credited by what left the inventory, not by what was meant to.
            local taken = QSF_Verify.take(player, obj.item, plan[i])
            given = given + QSF_add(run, i, obj.count, username, taken)
        end
    end

    if given == 0 then return nil, "NothingToGive" end

    QSF_Bridge.emit("globalContributed", { username = username, key = key, title = def.title, amount = given })

    -- last: this is what finishes the quest when that was the end of it.
    QSF_moved(key, username, true)

    return given
end

-- prog is by objective position, the same as a player's own, so a changed list cannot keep
-- its counters. who took part is kept: they did, whatever the objectives are now.
function QSF_Global.reconcile()
    for key, run in pairs(QSF_Global.ensure().runs) do
        local def = QSF_Defs.global[key]

        if def and run.status == "active" and run.sig ~= def.sig then
            QSF.warn("global quest " .. key .. ": objectives changed, shared progress reset")
            run.prog = QSF_Rules.blankProgress(def)
            run.sig = def.sig
        end
    end

    -- straight away, so an auto quest somebody just wrote starts on the reload.
    QSF_Global.tick()
end

-- auto only ever starts a quest that has never run. a second run is an admin's to ask for.
function QSF_Global.tick()
    if not QSF_Global.ready or not QSF_Defs.loaded then return end

    local data = QSF_Global.ensure()

    for _, def in ipairs(QSF_Defs.globalOrdered) do
        if def.start == "auto" and not data.runs[def.key] then
            QSF_Global.start(def.key)
        end
    end

    local now = getTimestampMs()

    for key, run in pairs(data.runs) do
        if run.status == "active" and run.ends and now >= run.ends then
            QSF_Global.finish(key, "expired")
        end
    end

    -- the throttle holds packets back, so something has to let the last one out.
    if not table.isempty(QSF_Global.dirty) then QSF_Global.flush() end
end

Events.OnInitGlobalModData.Add(function()
    QSF_Global.ensure()
    QSF_Global.ready = true
    QSF_Global.reconcile()
end)

Events.EveryOneMinute.Add(QSF_Global.tick)
