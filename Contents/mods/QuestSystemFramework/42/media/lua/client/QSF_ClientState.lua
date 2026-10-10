----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"

QSF_ClientState = QSF_ClientState or {}

QSF_ClientState.defs = QSF_ClientState.defs or {}
QSF_ClientState.ordered = QSF_ClientState.ordered or {}
QSF_ClientState.state = QSF_ClientState.state or {}
QSF_ClientState.collect = QSF_ClientState.collect or {}
QSF_ClientState.byGiver = QSF_ClientState.byGiver or {}
QSF_ClientState.npcs = QSF_ClientState.npcs or {}
QSF_ClientState.npcIds = QSF_ClientState.npcIds or {}
QSF_ClientState.globalDefs = QSF_ClientState.globalDefs or {}
QSF_ClientState.globalOrdered = QSF_ClientState.globalOrdered or {}
QSF_ClientState.global = QSF_ClientState.global or {}
QSF_ClientState.ready = false
QSF_ClientState.revision = 0

QSF_ClientState.lastToast = nil

local function QSF_touch()
    QSF_ClientState.revision = QSF_ClientState.revision + 1
end

QSF_ClientState.touch = QSF_touch

local handlers = {}

-- a list arrives in pieces and is held back until the last one, so a half-delivered set
-- never reaches a window. then it replaces what was there whole: a reload that dropped
-- something has to drop it here too, which a merge never would.
local function QSF_staged(field, done)
    local pending = nil

    return function(args)
        if not args then return end

        if not pending or args.i == 1 then pending = {} end

        for _, entry in ipairs(args[field] or {}) do
            pending[entry.key] = entry
        end

        if args.i >= args.n then
            local whole = pending
            pending = nil
            done(whole)
            QSF_touch()
        end
    end
end

handlers.defs = QSF_staged("quests", function(defs)
    QSF_ClientState.defs = defs
    QSF_ClientState.ordered = QSF_Rules.sorted(defs)

    -- what each npc hands out, in the order the log would list it. the marker asks every
    -- second for every npc, which is too often to go through every quest looking.
    local byGiver = {}
    for _, def in ipairs(QSF_ClientState.ordered) do
        if def.giver then
            byGiver[def.giver] = byGiver[def.giver] or {}
            table.insert(byGiver[def.giver], def)
        end
    end
    QSF_ClientState.byGiver = byGiver
end)

handlers.gdefs = QSF_staged("quests", function(defs)
    QSF_ClientState.globalDefs = defs
    QSF_ClientState.globalOrdered = QSF_Rules.sorted(defs)
end)

handlers.npcs = QSF_staged("npcs", function(npcs)
    QSF_ClientState.npcs = npcs
end)

-- which zombie each npc is. kept apart from the list because it arrives on its own
-- whenever the server stands a body up.
function handlers.npcIds(args)
    QSF_ClientState.npcIds = (args and args.ids) or {}
    QSF_touch()
end

function handlers.state(args)
    QSF_ClientState.state = (args and args.quests) or {}
    QSF_ClientState.ready = true
    QSF_touch()
end

function handlers.delta(args)
    if not args or not args.key then return end

    if args.rec == false then
        QSF_ClientState.state[args.key] = nil
    else
        QSF_ClientState.state[args.key] = args.rec
    end

    QSF_touch()
end

-- the server says how long a global quest has left rather than when it ends, since its
-- clock is not this one. pinned to this machine's on arrival and counted down from there.
local function QSF_pin(run)
    if run.left then run.endsAt = getTimestampMs() + run.left end
    return run
end

function handlers.gstate(args)
    local runs = {}
    for key, run in pairs((args and args.runs) or {}) do runs[key] = QSF_pin(run) end

    QSF_ClientState.global = runs
    QSF_touch()
end

-- one packet for everybody, so it cannot say what this player put in. that is kept from
-- the last one that did, unless the quest has started over since.
function handlers.gdelta(args)
    if not args or not args.key or not args.run then return end

    local run = args.run
    local before = QSF_ClientState.global[args.key]

    if run.mine == nil then
        run.mine = (before and before.run == run.run) and before.mine or 0
    end

    QSF_ClientState.global[args.key] = QSF_pin(run)
    QSF_touch()
end

function handlers.gmine(args)
    local run = args and args.key and QSF_ClientState.global[args.key] or nil
    if not run then return end

    run.mine = args.mine or 0
    QSF_touch()
end

-- the server has already authorised and moved its own copy. this is the leg that sticks,
-- since a client owns its player's position and the server would only rubber-band a
-- move it did not make itself.
function handlers.teleport(args)
    if not args or type(args.x) ~= "number" or type(args.y) ~= "number" then return end

    local player = getPlayer()
    if not player then return end

    player:teleportTo(args.x, args.y, args.z or 0)
end

function handlers.toast(args)
    QSF_ClientState.lastToast = args
    QSF_touch()

    -- looked up at call time: the notice borrows the windows' wording, and those load
    -- after this file does.
    if QSF_Notice then QSF_Notice.show(args) end
end

function QSF_ClientState.onCommand(module, command, args)
    if module ~= QSF.MODULE then return end

    local handler = handlers[command]
    if not handler then return end

    local ok, err = pcall(handler, args)
    if not ok then QSF.warn("client command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

function QSF_ClientState.record(key)
    return QSF_ClientState.state[key]
end

function QSF_ClientState.counts()
    return QSF_ClientState.collect
end

-- what a quest is to this player right now. the log, the conversation and the marker all
-- ask it here, of the same records and the same counts.
function QSF_ClientState.stateOf(def, player)
    return QSF_Rules.questState(def, QSF_ClientState.state[def.key], player,
        QSF_ClientState.state, QSF_ClientState.collect)
end

-- what one npc hands out, in the order the log would list it.
function QSF_ClientState.questsOf(npcKey)
    return QSF_ClientState.byGiver[npcKey] or {}
end

-- everything a window asks for with a key and nothing else. whether it may is the server's
-- to decide, and the answer comes back as a delta or a refusal.
for _, command in ipairs({ "accept", "abandon", "teleport", "globalGive", "globalStart", "globalEnd" }) do
    QSF_ClientState[command] = function(key)
        QSF_Net.toServer(command, { key = key })
    end
end

-- pick is the reward option the player chose, and is absent on quests without a pool and
-- on the poll's auto-claim nudge, neither of which can reach a quest that has one.
function QSF_ClientState.claim(key, pick)
    QSF_Net.toServer("claim", { key = key, pick = pick })
end

function QSF_ClientState.reload()
    QSF_Net.toServer("reload", {})
end

Events.OnServerCommand.Add(QSF_ClientState.onCommand)

-- OnCreatePlayer, not OnGameStart: the handshake needs a player on both ends.
Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum ~= 0 then return end
    QSF_Net.toServer("hello", {})
end)
