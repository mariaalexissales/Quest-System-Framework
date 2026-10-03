----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"
require "QSF_State"
require "QSF_Verify"
require "QSF_Kills"
require "QSF_Npcs"

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
            giver = def.giver,
            dialogue = def.dialogue,
            sig = def.sig,
        }
    end

    return wire
end

-- sorted, because pairs() would hand every client the list in a different order.
local function QSF_wireNpcs()
    local wire = {}

    for _, npc in pairs(QSF_Defs.npcs) do
        wire[#wire + 1] = {
            key = npc.key,
            name = npc.name,
            x = npc.x,
            y = npc.y,
            z = npc.z,
            outfit = npc.outfit,
            female = npc.female,
            skin = npc.skin,
            facing = npc.facing,
            greeting = npc.greeting,
            placed = npc.placed,
        }
    end

    table.sort(wire, function(a, b) return a.key < b.key end)

    return wire
end

-- an empty list still goes out as one piece, so a reload that removed the last of
-- something reaches the client as "none" rather than as nothing at all.
local function QSF_sendPieces(player, command, field, wire)
    local total = math.max(1, math.ceil(#wire / CHUNK))

    for index = 1, total do
        local piece = {}
        for offset = 1, CHUNK do
            local at = (index - 1) * CHUNK + offset
            if wire[at] then piece[#piece + 1] = wire[at] end
        end
        QSF_Net.toClient(player, command, { i = index, n = total, [field] = piece })
    end
end

function QSF_Commands.sendDefs(player)
    QSF_sendPieces(player, "defs", "quests", QSF_wireDefs())
end

-- the ids go separately. they change whenever a body is first stood up, long after the
-- list itself has stopped moving.
function QSF_Commands.sendNpcs(player)
    QSF_sendPieces(player, "npcs", "npcs", QSF_wireNpcs())
    QSF_Npcs.sendIds(player)
end

QSF_Commands.handlers = {}

function QSF_Commands.handlers.hello(player)
    if not player or not player:getUsername() then return end

    QSF_State.reconcile(player:getUsername(), QSF_Defs.all)
    QSF_Commands.sendDefs(player)
    QSF_Commands.sendNpcs(player)
    QSF_State.sendSnapshot(player)
end

function QSF_Commands.handlers.accept(player, args)
    if not player or not args or not args.key then return end

    local username = player:getUsername()
    local def = QSF_Defs.get(args.key)
    if not def then return end

    local quests = QSF_State.forPlayer(username)
    local ok, reason, detail, extra = QSF_Rules.canAccept(def, quests[args.key], player, quests)

    if not ok then
        -- the client greys these rows with the same function, so this is a stale window
        -- or somebody going around the ui. the detail goes too, so it can say what is missing.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason,
            detail = detail, extra = extra })
        return
    end

    -- measured against the server's own npc and the player it can see. the dialogue only
    -- opens in reach, so this is a window left open while walking off, or a crafted packet.
    if not QSF_Rules.atGiver(def, QSF_Defs.npcs, player) then
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = "TooFar" })
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
    local ok, reason, hours = QSF_Rules.canTeleport(def, quests[args.key])

    if not ok then
        -- the client greys the button with the same function, so this is a stale window.
        QSF_Net.toClient(player, "toast", { kind = "refused", key = args.key, reason = reason, detail = hours })
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

    -- an ordinal into this quest's own reward pool, not an item name. anything else is
    -- refused by QSF_Rules.pickedReward rather than clamped into a payout nobody chose.
    local ok, reason = QSF_Verify.claim(player, args.key, args.pick)

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

-- everything that changes what is defined ends here: read the files again, stand the
-- npcs up or take them away, and tell everybody.
local function QSF_reloadAll(player)
    QSF_Defs.load()

    -- straight away, so an npc taken out of the files is gone before the reply lands.
    local ok, err = pcall(QSF_Npcs.ensure)
    if not ok then QSF.warn("npc pass failed: " .. tostring(err)) end

    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local other = players:get(i)
            QSF_State.reconcile(other:getUsername(), QSF_Defs.all)
            QSF_Commands.sendDefs(other)
            QSF_Commands.sendNpcs(other)
            QSF_State.sendSnapshot(other)
        end
    else
        QSF_State.reconcile(player:getUsername(), QSF_Defs.all)
        QSF_Commands.sendDefs(player)
        QSF_Commands.sendNpcs(player)
        QSF_State.sendSnapshot(player)
    end
end

-- the buttons are only drawn for admins, but the client draws the buttons.
local function QSF_adminOnly(player, what)
    if QSF.isAdmin(player) then return true end

    QSF.warn(tostring(player and player:getUsername()) .. " asked to " .. what .. " without permission")
    return false
end

function QSF_Commands.handlers.reload(player)
    if not QSF_adminOnly(player, "reload") then return end

    QSF_reloadAll(player)
    QSF_Net.toClient(player, "toast", { kind = "reloaded" })
end

-- the tile is the admin's to choose, so unlike everywhere else the coordinates in the
-- packet are the point. everything else about the entry is held to the same standard as
-- one read out of a file.
function QSF_Commands.handlers.npcPlace(player, args)
    if not QSF_adminOnly(player, "place an npc") then return end
    if type(args) ~= "table" then return end

    local npc, errors = QSF_Schema.normaliseNpc(args, QSF.NPC_FILE)

    for _, message in ipairs(errors or {}) do QSF.warn(message) end

    if not npc then
        QSF_Net.toClient(player, "toast", { kind = "refused", reason = "BadNpc" })
        return
    end

    -- the form checks this too, against a list that may be a reload behind.
    if QSF_Defs.npc(npc.key) then
        QSF_Net.toClient(player, "toast", { kind = "refused", key = npc.key, reason = "KeyTaken" })
        return
    end

    local placed = QSF_Defs.placed()
    placed[#placed + 1] = npc

    if not QSF_Defs.writePlaced(placed) then
        QSF_Net.toClient(player, "toast", { kind = "refused", key = npc.key, reason = "WriteFailed" })
        return
    end

    QSF.log(tostring(player:getUsername()) .. " placed npc " .. npc.key
        .. " at " .. npc.x .. "," .. npc.y .. "," .. npc.z)

    -- back through the file rather than straight into the table, so what is standing in
    -- the world is only ever what the files say.
    QSF_reloadAll(player)
end

-- only ones the game placed. a hand-written npc is taken out of the file it was written
-- in, by whoever wrote it.
function QSF_Commands.handlers.npcRemove(player, args)
    if not QSF_adminOnly(player, "remove an npc") then return end

    local npc = args and QSF_Defs.npc(args.key) or nil
    if not npc or not npc.placed then return end

    local kept = {}
    for _, other in ipairs(QSF_Defs.placed()) do
        if other.key ~= npc.key then kept[#kept + 1] = other end
    end

    if not QSF_Defs.writePlaced(kept) then
        QSF_Net.toClient(player, "toast", { kind = "refused", key = npc.key, reason = "WriteFailed" })
        return
    end

    QSF.log(tostring(player:getUsername()) .. " removed npc " .. npc.key)

    QSF_reloadAll(player)
    QSF_Npcs.forget(npc.key)
end

local function QSF_onClientCommand(module, command, player, args)
    if module ~= QSF.MODULE then return end

    local handler = QSF_Commands.handlers[command]
    if not handler then return end

    local ok, err = pcall(handler, player, args)
    if not ok then QSF.warn("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

Events.OnClientCommand.Add(QSF_onClientCommand)
