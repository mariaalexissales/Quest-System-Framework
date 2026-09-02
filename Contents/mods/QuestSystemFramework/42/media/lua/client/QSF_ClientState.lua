----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"

-- the client's cache of what the server told it. plain lua tables, never mod data: this
-- side has no authority, so nothing here is worth saving and everything here is replaced
-- the moment the server says otherwise.

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

-- definitions arrive in pieces because a full set is more text than one command should
-- carry. they are collected into a staging table so a half-delivered set never shows.
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

-- ---------------------------------------------------------------------------
-- convenience the ui reads
-- ---------------------------------------------------------------------------

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

function QSF_ClientState.reload()
    QSF_Net.toServer("reload", {})
end

Events.OnServerCommand.Add(QSF_ClientState.onCommand)

-- asked for on OnCreatePlayer rather than OnGameStart, because the handshake needs a
-- player object to exist on both ends.
Events.OnCreatePlayer.Add(function(playerNum)
    if playerNum ~= 0 then return end
    QSF_Net.toServer("hello", {})
end)
