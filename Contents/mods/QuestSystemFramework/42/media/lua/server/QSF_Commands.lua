----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"
require "QSF_State"
require "QSF_Verify"
require "QSF_Kills"

-- everything a client can ask the server to do, in one table. the shape follows vanilla's
-- media/lua/server/ClientCommands.lua: a table of handlers and one dispatcher.
--
-- in singleplayer QSF_Net calls straight into this table, so these handlers are the only
-- implementation of accept, abandon and claim that exists anywhere.

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Commands = QSF_Commands or {}

-- definitions are sent in pieces. a hundred quests is more text than one command should
-- carry, and the reassembly on the far side is cheap.
local CHUNK = 8
local CLAIM_COOLDOWN_MS = 3000

-- runtime only, deliberately not in mod data: a rate limit should not survive a restart
-- or bloat the world save.
local lastClaim = {}

local function QSF_nowMs()
    local ok, ms = pcall(function() return getTimestampMs() end)
    if ok and ms then return ms end
    return 0
end

-- descriptions travel too; the client has no files of its own to read them from.
local function QSF_wireDefs()
    local wire = {}

    for _, def in ipairs(QSF_Defs.ordered) do
        wire[#wire + 1] = {
            key = def.key,
            title = def.title,
            description = def.description,
            order = def.order,
            location = def.location,
            prereqs = def.prereqs,
            objectives = def.objectives,
            rewards = def.rewards,
            repeatable = def.repeatable,
            autoComplete = def.autoComplete,
            sig = def.sig,
        }
    end

    return wire
end

function QSF_Commands.sendDefs(player)
    local wire = QSF_wireDefs()
    local total = math.max(1, math.ceil(#wire / CHUNK))

    for index = 1, total do
        local piece = {}
        for offset = 1, CHUNK do
            local at = (index - 1) * CHUNK + offset
            if wire[at] then piece[#piece + 1] = wire[at] end
        end
        QSF_Net.toClient(player, "defs", { i = index, n = total, quests = piece })
    end
end

QSF_Commands.handlers = {}

function QSF_Commands.handlers.hello(player)
    if not player or not player:getUsername() then return end

    QSF_State.reconcile(player:getUsername(), QSF_Defs.all)
    QSF_Commands.sendDefs(player)
    QSF_State.sendSnapshot(player)
end

function QSF_Commands.handlers.accept(player, args)
    if not player or not args or not args.key then return end

    local username = player:getUsername()
    local def = QSF_Defs.get(args.key)
    if not def then return end

    local quests = QSF_State.forPlayer(username)
    local ok, reason = QSF_Rules.canAccept(def, quests[args.key], player, quests)

    if not ok then
        -- the client greys the same rows using the same function, so this only fires on
        -- a stale window or a client that went around the ui.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason })
        return
    end

    QSF_State.accept(username, def)
    QSF_State.push(username, args.key)
    QSF_Net.toClient(player, "toast", { kind = "accepted", key = args.key })
end

function QSF_Commands.handlers.abandon(player, args)
    if not player or not args or not args.key then return end

    QSF_State.abandon(player:getUsername(), args.key)
    QSF_State.push(player:getUsername(), args.key)
end

function QSF_Commands.handlers.claim(player, args)
    if not player or not args or not args.key then return end

    local username = player:getUsername()
    local now = QSF_nowMs()
    local mark = username .. "/" .. args.key

    if now - (lastClaim[mark] or 0) < CLAIM_COOLDOWN_MS then return end
    lastClaim[mark] = now

    local ok, reason = QSF_Verify.claim(player, args.key)

    if ok then
        QSF_Net.toClient(player, "toast", { kind = "completed", key = args.key })
    elseif reason ~= "Incomplete" then
        -- an incomplete claim is just the client polling ahead of the server; anything
        -- else is worth telling the player about.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason })
    end
end

function QSF_Commands.handlers.kills(player, args)
    QSF_Kills.onReported(player, args)
end

function QSF_Commands.handlers.reload(player)
    -- the button is only drawn for admins, but the button is drawn by the client, so the
    -- decision is made again here where it cannot be edited.
    if not QSF.isAdmin(player) then
        QSF.warn(tostring(player and player:getUsername()) .. " asked for a reload without permission")
        return
    end

    QSF_Defs.load()

    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local other = players:get(i)
            QSF_State.reconcile(other:getUsername(), QSF_Defs.all)
            QSF_Commands.sendDefs(other)
            QSF_State.sendSnapshot(other)
        end
    else
        QSF_State.reconcile(player:getUsername(), QSF_Defs.all)
        QSF_Commands.sendDefs(player)
        QSF_State.sendSnapshot(player)
    end

    QSF_Net.toClient(player, "toast", { kind = "reloaded" })
end

local function QSF_onClientCommand(module, command, player, args)
    if module ~= QSF.MODULE then return end

    local handler = QSF_Commands.handlers[command]
    if not handler then return end

    local ok, err = pcall(handler, player, args)
    if not ok then QSF.warn("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

Events.OnClientCommand.Add(QSF_onClientCommand)
