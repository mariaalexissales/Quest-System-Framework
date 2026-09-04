----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"
require "QSF_State"
require "QSF_Verify"
require "QSF_Kills"

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Commands = QSF_Commands or {}

-- a hundred quests is more text than one command should carry.
local CHUNK = 8
local CLAIM_COOLDOWN_MS = 3000

-- runtime only. a rate limit has no business surviving a restart or sitting in the save.
local lastClaim = {}

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
            teleport = def.teleport,
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
        -- the client greys these rows with the same function, so this is a stale window
        -- or somebody going around the ui.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason })
        return
    end

    QSF_State.accept(username, def)
    QSF_State.push(username, args.key)
    QSF_Net.toClient(player, "toast", { kind = "accepted", key = args.key })
end

-- the client sends a key and nothing else. the coordinates are read from the server's own
-- def, so a crafted packet cannot ask to be put somewhere the quest never named.
function QSF_Commands.handlers.teleport(player, args)
    if not player or not args or not args.key then return end

    local username = player:getUsername()
    local def = QSF_Defs.get(args.key)
    if not def or not def.teleport then return end

    local quests = QSF_State.forPlayer(username)
    local ok, reason = QSF_Rules.canTeleport(def, quests[args.key])

    if not ok then
        -- the client greys the button with the same function, so this is a stale window.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason })
        return
    end

    local spot = def.teleport

    -- chunk coordinates are world coordinates over ten. the same test the vanilla map makes
    -- before it offers a teleport at all.
    if not getWorld():getMetaGrid():isValidChunk(spot.x / 10, spot.y / 10) then
        QSF.warn(args.key .. ": teleport points outside the map at " .. spot.x .. "," .. spot.y)
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = "OffMap" })
        return
    end

    -- stamped before the move, so a cooldown still starts if the teleport itself throws.
    QSF_State.markTeleport(username, args.key)
    QSF_State.push(username, args.key)

    -- half a tile lands them on the centre rather than the corner.
    local x, y = spot.x + 0.5, spot.y + 0.5

    -- singleplayer runs the client leg of this anyway, and moving the same player twice
    -- would be pointless rather than harmful.
    if isServer() then
        local moved = pcall(function() player:teleportTo(x, y, spot.z) end)
        if not moved then QSF.warn("server could not teleport " .. username) end
    end

    QSF_Net.toClient(player, "teleport", { key = args.key, x = x, y = y, z = spot.z })
end

function QSF_Commands.handlers.abandon(player, args)
    if not player or not args or not args.key then return end

    QSF_State.abandon(player:getUsername(), args.key)
    QSF_State.push(player:getUsername(), args.key)
end

function QSF_Commands.handlers.claim(player, args)
    if not player or not args or not args.key then return end

    local username = player:getUsername()
    local now = getTimestampMs()
    local mark = username .. "/" .. args.key

    if now - (lastClaim[mark] or 0) < CLAIM_COOLDOWN_MS then return end
    lastClaim[mark] = now

    local ok, reason = QSF_Verify.claim(player, args.key)

    if ok then
        QSF_Net.toClient(player, "toast", { kind = "completed", key = args.key })
    elseif reason ~= "Incomplete" then
        -- an incomplete claim is just the client polling ahead of the server.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason })
    end
end

function QSF_Commands.handlers.kills(player, args)
    QSF_Kills.onReported(player, args)
end

function QSF_Commands.handlers.reload(player)
    -- the button is only drawn for admins, but the client draws the button.
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
