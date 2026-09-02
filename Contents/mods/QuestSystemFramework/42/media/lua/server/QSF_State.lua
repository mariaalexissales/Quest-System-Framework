----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"

-- the authority's copy of who is doing what. lives in world-saved global mod data keyed
-- by username, deliberately not in player:getModData(): on a multiplayer client that is
-- the client's own copy, never pushed up, so a player could edit it freely and the server
-- would have no way to know.

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_State = QSF_State or {}

local TABLE_NAME = "QSF_PlayerState"
local FLUSH_MS = 2000

QSF_State.data = QSF_State.data or nil
QSF_State.dirty = QSF_State.dirty or {}
QSF_State.lastFlush = QSF_State.lastFlush or {}

local function QSF_now()
    local ok, ms = pcall(function() return getTimestampMs() end)
    if ok and ms then return ms end
    -- getTimestampMs is the name used elsewhere in b42, but fall back rather than error
    -- if this build disagrees; the throttle degrades to "always flush", never to a crash.
    return 0
end

function QSF_State.ensure()
    if not QSF_State.data then
        QSF_State.data = ModData.getOrCreate(TABLE_NAME)
    end
    return QSF_State.data
end

function QSF_State.forPlayer(username)
    if not username then return nil end

    local all = QSF_State.ensure()
    local entry = all[username]

    if not entry then
        entry = { v = QSF.SCHEMA_V, quests = {} }
        all[username] = entry
    end

    -- an older save may predate a field; quests is the only one anything reads.
    if not entry.quests then entry.quests = {} end

    return entry.quests
end

function QSF_State.record(username, key)
    local quests = QSF_State.forPlayer(username)
    return quests and quests[key] or nil
end

-- progress ordinals only mean anything against the objective list they were recorded
-- for. if an admin reorders or retunes the objectives the signature moves, and stale
-- counters get zeroed rather than silently credited to the wrong objective.
function QSF_State.reconcile(username, defs)
    local quests = QSF_State.forPlayer(username)
    if not quests then return end

    for key, rec in pairs(quests) do
        local def = defs and defs[key]

        if def and rec.status == "active" and rec.sig and rec.sig ~= def.sig then
            QSF.warn(username .. ": objectives for " .. key .. " changed, progress reset")
            rec.prog = {}
            for i = 1, #def.objectives do rec.prog[i] = 0 end
            rec.sig = def.sig
        end
    end
end

function QSF_State.accept(username, def)
    local quests = QSF_State.forPlayer(username)
    if not quests then return nil end

    local existing = quests[def.key]

    local rec = {
        status = "active",
        sig = def.sig,
        started = QSF_Rules.worldHours(),
        turnins = existing and existing.turnins or 0,
        prog = {},
    }

    -- dense from 1 and never nil. these are kahlua tables and a hole in an array is a
    -- reliable way to lose everything after it.
    for i = 1, #def.objectives do rec.prog[i] = 0 end

    quests[def.key] = rec
    return rec
end

function QSF_State.abandon(username, key)
    local quests = QSF_State.forPlayer(username)
    if not quests then return end

    local rec = quests[key]
    if not rec or rec.status ~= "active" then return end

    -- a quest turned in before keeps its completed record; one never finished disappears.
    if (rec.turnins or 0) > 0 then
        quests[key] = { status = "done", done = rec.done, turnins = rec.turnins }
    else
        quests[key] = nil
    end
end

function QSF_State.complete(username, key)
    local quests = QSF_State.forPlayer(username)
    if not quests then return end

    local rec = quests[key]
    if not rec then return end

    -- compacted on purpose: a long-lived server should not carry a counter array for
    -- every quest every player has ever finished.
    quests[key] = {
        status = "done",
        done = QSF_Rules.worldHours(),
        turnins = (rec.turnins or 0) + 1,
    }
end

-- bumps one kill counter, capped. without the cap a long-running quest accumulates an
-- unbounded integer in the world save for no benefit.
function QSF_State.addKill(username, key, index, cap)
    local rec = QSF_State.record(username, key)
    if not rec or rec.status ~= "active" or not rec.prog then return false end

    local have = rec.prog[index] or 0
    if have >= cap then return false end

    rec.prog[index] = have + 1
    return rec.prog[index] >= cap
end

-- ---------------------------------------------------------------------------
-- pushing state to the client
-- ---------------------------------------------------------------------------

local function QSF_playerByName(username)
    if not isServer() then return getPlayer() end

    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local player = players:get(i)
        if player:getUsername() == username then return player end
    end

    return nil
end

QSF_State.playerByName = QSF_playerByName

function QSF_State.sendSnapshot(player)
    if not player then return end

    local quests = QSF_State.forPlayer(player:getUsername())
    QSF_Net.toClient(player, "state", { quests = quests or {} })
end

function QSF_State.push(username, key)
    local player = QSF_playerByName(username)
    if not player then return end

    local rec = QSF_State.record(username, key)
    QSF_Net.toClient(player, "delta", { key = key, rec = rec or false })

    QSF_State.dirty[username] = QSF_State.dirty[username] or {}
    QSF_State.dirty[username][key] = nil
    QSF_State.lastFlush[username] = QSF_now()
end

-- a player clearing a horde would otherwise send one packet per kill. urgent skips the
-- throttle, because a counter hitting its target has to show up immediately or the ui
-- looks stuck at the moment it matters most.
function QSF_State.markDirty(username, key, urgent)
    local now = QSF_now()
    local last = QSF_State.lastFlush[username] or 0

    if urgent or (now - last) >= FLUSH_MS then
        QSF_State.push(username, key)
        return
    end

    QSF_State.dirty[username] = QSF_State.dirty[username] or {}
    QSF_State.dirty[username][key] = true
end

function QSF_State.flushAll()
    for username, keys in pairs(QSF_State.dirty) do
        for key in pairs(keys) do
            QSF_State.push(username, key)
        end
        QSF_State.dirty[username] = nil
    end
end

Events.OnInitGlobalModData.Add(function()
    QSF_State.ensure()
end)

-- the throttle holds packets back, so something has to let the last one out.
Events.EveryOneMinute.Add(QSF_State.flushAll)
