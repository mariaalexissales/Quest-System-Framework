----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"

QSF = QSF or {}
QSF_ClientState = QSF_ClientState or {}

QSF_ClientState.defs = QSF_ClientState.defs or {}
QSF_ClientState.ordered = QSF_ClientState.ordered or {}
QSF_ClientState.state = QSF_ClientState.state or {}
QSF_ClientState.collect = QSF_ClientState.collect or {}
QSF_ClientState.ready = false
QSF_ClientState.revision = 0

QSF_ClientState.lastToast = nil

local pending = nil

local function QSF_touch()
    QSF_ClientState.revision = QSF_ClientState.revision + 1
end

QSF_ClientState.touch = QSF_touch

local function QSF_reorder()
    local ordered = {}
    for _, def in pairs(QSF_ClientState.defs) do ordered[#ordered + 1] = def end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)

    QSF_ClientState.ordered = ordered
end

local handlers = {}

-- staged, so a half-delivered set never reaches the window.
function handlers.defs(args)
    if not args then return end

    if not pending or args.i == 1 then pending = {} end

    for _, def in ipairs(args.quests or {}) do
        pending[def.key] = def
    end

    if args.i >= args.n then
        QSF_ClientState.defs = pending
        pending = nil
        QSF_reorder()
        QSF_touch()
    end
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

function QSF_ClientState.accept(key)
    QSF_Net.toServer("accept", { key = key })
end

function QSF_ClientState.abandon(key)
    QSF_Net.toServer("abandon", { key = key })
end

function QSF_ClientState.claim(key)
    QSF_Net.toServer("claim", { key = key })
end

function QSF_ClientState.teleport(key)
    QSF_Net.toServer("teleport", { key = key })
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
