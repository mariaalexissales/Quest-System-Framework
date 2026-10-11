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
require "QSF_Global"
require "QSF_Bridge"

if not QSF.isAuthority() then return end

QSF_Commands = QSF_Commands or {}

-- a hundred quests is more text than one command should carry.
local CHUNK = 8
local ASK_COOLDOWN_MS = 3000

-- what a client is sent of each thing. descriptions travel too; the client has no files of
-- its own to read them from.
local QUEST_FIELDS = { "key", "title", "description", "order", "location", "teleport", "prereqs",
    "objectives", "rewards", "repeatable", "autoComplete", "giver", "dialogue", "sig" }

local GLOBAL_FIELDS = { "key", "title", "description", "order", "location", "objectives", "rewards",
    "consolation", "start", "durationHours", "minContribution", "sig" }

-- an npc goes out the way it would be written into a file, plus whether the game placed it.
local NPC_FIELDS = { "placed" }
for _, field in ipairs(QSF_Defs.NPC_FIELDS) do NPC_FIELDS[#NPC_FIELDS + 1] = field end

local function QSF_wire(list, fields)
    local wire = {}

    for index, entry in ipairs(list) do
        local out = {}
        for _, field in ipairs(fields) do out[field] = entry[field] end
        wire[index] = out
    end

    return wire
end

-- built once per read of the files rather than once per player: a reload on a full server
-- sends the same three lists to everybody on it.
local wired = { revision = -1 }

local function QSF_wired()
    if wired.revision ~= QSF_Defs.revision then
        wired = {
            revision = QSF_Defs.revision,
            quests = QSF_wire(QSF_Defs.ordered, QUEST_FIELDS),
            global = QSF_wire(QSF_Defs.globalOrdered, GLOBAL_FIELDS),
            npcs = QSF_wire(QSF_Defs.npcList(), NPC_FIELDS),
        }
    end

    return wired
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
    QSF_sendPieces(player, "defs", "quests", QSF_wired().quests)
end

-- the ids go separately. they change whenever a body is first stood up, long after the
-- list itself has stopped moving.
function QSF_Commands.sendNpcs(player)
    QSF_sendPieces(player, "npcs", "npcs", QSF_wired().npcs)
    QSF_Npcs.sendIds(player)
end

-- the quests, then where each one has got to and what this player has put in.
function QSF_Commands.sendGlobal(player)
    QSF_sendPieces(player, "gdefs", "quests", QSF_wired().global)
    QSF_Global.sendSnapshot(player)
end

-- the client greys what it can with the same rules, so a refusal is a stale window or
-- somebody going around the ui. it is told why either way, and what it was short of.
local function QSF_refuse(player, key, reason, detail, extra)
    QSF_Net.toClient(player, "toast", { kind = "refused", key = key, reason = reason,
        detail = detail, extra = extra })
end

-- most of what a client asks for is about one thing, named by its key. the handler is
-- handed that key, and is never reached without one.
local function QSF_keyed(handler)
    return function(player, args)
        if not player or not args or not args.key then return end
        return handler(player, args.key, args)
    end
end

-- the buttons are only drawn for admins, but the client draws the buttons.
local function QSF_admin(what, handler)
    return function(player, args)
        if QSF.isAdmin(player) then return handler(player, args) end

        QSF.warn(tostring(player and player:getUsername()) .. " asked to " .. what .. " without permission")
    end
end

-- runtime only. a rate limit has no business surviving a restart or sitting in the save.
local lastAsked = {}

-- true for the same thing asked again a moment later: a held button, or a script.
local function QSF_tooSoon(mark)
    local now = getTimestampMs()
    if now - (lastAsked[mark] or 0) < ASK_COOLDOWN_MS then return true end

    lastAsked[mark] = now
    return false
end

QSF_Commands.handlers = {}

-- everything one player needs to be looking at what the server has now.
function QSF_Commands.sync(player)
    QSF_State.reconcile(player:getUsername(), QSF_Defs.all)
    QSF_Commands.sendDefs(player)
    QSF_Commands.sendNpcs(player)
    QSF_State.sendSnapshot(player)
    QSF_Commands.sendGlobal(player)

    -- last, so whatever ended while they were away is paid to somebody who can already
    -- see what it was.
    QSF_Global.settle(player)
end

function QSF_Commands.handlers.hello(player)
    if not player or not player:getUsername() then return end

    QSF_Commands.sync(player)
end

QSF_Commands.handlers.accept = QSF_keyed(function(player, key)
    local username = player:getUsername()
    local def = QSF_Defs.get(key)
    if not def then return end

    local quests = QSF_State.forPlayer(username)
    local ok, reason, detail, extra = QSF_Rules.canAccept(def, quests[key], player, quests)

    if not ok then
        QSF_refuse(player, key, reason, detail, extra)
        return
    end

    -- measured against the server's own npc and the player it can see. the dialogue only
    -- opens in reach, so this is a window left open while walking off, or a crafted packet.
    if not QSF_Rules.atGiver(def, QSF_Defs.npcs, player) then
        QSF_refuse(player, key, "TooFar")
        return
    end

    QSF_State.accept(username, def)
    QSF_State.push(username, key)
    QSF_Net.toClient(player, "toast", { kind = "accepted", key = key })
    QSF_Bridge.emit("questAccepted", { username = username, key = key, title = def.title })
end)

-- the client sends a key and nothing else. the coordinates are read from the server's own
-- def, so a crafted packet cannot ask to be put somewhere the quest never named.
QSF_Commands.handlers.teleport = QSF_keyed(function(player, key)
    local username = player:getUsername()
    local def = QSF_Defs.get(key)
    if not def or not def.teleport then return end

    local quests = QSF_State.forPlayer(username)
    local ok, reason, hours = QSF_Rules.canTeleport(def, quests[key])

    if not ok then
        QSF_refuse(player, key, reason, hours)
        return
    end

    local spot = def.teleport

    -- chunk coordinates are world coordinates over ten. the same test the vanilla map makes
    -- before it offers a teleport at all.
    if not getWorld():getMetaGrid():isValidChunk(spot.x / 10, spot.y / 10) then
        QSF.warn(key .. ": teleport points outside the map at " .. spot.x .. "," .. spot.y)
        QSF_refuse(player, key, "OffMap")
        return
    end

    -- stamped before the move, so a cooldown still starts if the teleport itself throws.
    QSF_State.markTeleport(username, key)
    QSF_State.push(username, key)

    -- half a tile lands them on the centre rather than the corner.
    local x, y = spot.x + 0.5, spot.y + 0.5

    -- singleplayer runs the client leg of this anyway, and moving the same player twice
    -- would be pointless rather than harmful.
    if isServer() then
        local moved = pcall(function() player:teleportTo(x, y, spot.z) end)
        if not moved then QSF.warn("server could not teleport " .. username) end
    end

    QSF_Net.toClient(player, "teleport", { key = key, x = x, y = y, z = spot.z })
end)

QSF_Commands.handlers.abandon = QSF_keyed(function(player, key)
    local username = player:getUsername()
    local dropped = QSF_State.abandon(username, key)

    QSF_State.push(username, key)

    if dropped then
        local def = QSF_Defs.get(key)
        QSF_Bridge.emit("questAbandoned", { username = username, key = key, title = def and def.title or key })
    end
end)

QSF_Commands.handlers.claim = QSF_keyed(function(player, key, args)
    if QSF_tooSoon(player:getUsername() .. "/" .. key) then return end

    -- an ordinal into this quest's own reward pool, not an item name. anything else is
    -- refused by QSF_Rules.pickedReward rather than clamped into a payout nobody chose.
    local ok, reason = QSF_Verify.claim(player, key, args.pick)

    -- an incomplete claim is just the client polling ahead of the server.
    if not ok and reason ~= "Incomplete" then QSF_refuse(player, key, reason) end
end)

function QSF_Commands.handlers.kills(player, args)
    QSF_Kills.onReported(player, args)
end

-- everything that changes what is defined ends here: read the files again, stand the
-- npcs up or take them away, and tell everybody.
local function QSF_reloadAll()
    QSF_Defs.load()
    QSF_Global.reconcile()

    -- straight away, so an npc taken out of the files is gone before the reply lands.
    local ok, err = pcall(QSF_Npcs.ensure)
    if not ok then QSF.warn("npc pass failed: " .. tostring(err)) end

    for _, player in ipairs(QSF_State.players()) do
        QSF_Commands.sync(player)
    end

    QSF_Bridge.emit("reloaded", { quests = #QSF_Defs.ordered, global = #QSF_Defs.globalOrdered,
        npcs = #QSF_Defs.npcList() })
end

QSF_Commands.handlers.reload = QSF_admin("reload", function(player)
    QSF_reloadAll()
    QSF_Net.toClient(player, "toast", { kind = "reloaded" })
end)

-- the client sends a key and nothing else. what the player holds and how much is still
-- missing are both the server's to count.
QSF_Commands.handlers.globalGive = QSF_keyed(function(player, key)
    if QSF_tooSoon(player:getUsername() .. "/global/" .. key) then return end

    local given, reason = QSF_Global.give(player, key)

    if not given then
        QSF_refuse(player, key, reason)
        return
    end

    QSF_Net.toClient(player, "toast", { kind = "globalGave", count = given })
end)

QSF_Commands.handlers.globalStart = QSF_admin("start a global quest", QSF_keyed(function(player, key)
    local ok, reason = QSF_Global.start(key)

    if not ok then
        QSF_refuse(player, key, reason)
        return
    end

    QSF.log(tostring(player:getUsername()) .. " started global quest " .. key)
end))

-- ended early is ended short, so it pays what running out of time would have.
QSF_Commands.handlers.globalEnd = QSF_admin("end a global quest", QSF_keyed(function(player, key)
    if QSF_Global.finish(key, "expired") then
        QSF.log(tostring(player:getUsername()) .. " ended global quest " .. key .. " early")
    end
end))

-- the tile is the admin's to choose, so unlike everywhere else the coordinates in the
-- packet are the point. everything else about the entry is held to the same standard as
-- one read out of a file.
QSF_Commands.handlers.npcPlace = QSF_admin("place an npc", function(player, args)
    if type(args) ~= "table" then return end

    local npc, errors = QSF_Schema.normaliseNpc(args, QSF.NPC_FILE)

    for _, message in ipairs(errors or {}) do QSF.warn(message) end

    if not npc then
        QSF_refuse(player, nil, "BadNpc")
        return
    end

    -- the form checks this too, against a list that may be a reload behind.
    if QSF_Defs.npc(npc.key) then
        QSF_refuse(player, npc.key, "KeyTaken")
        return
    end

    local placed = QSF_Defs.npcList(true)
    placed[#placed + 1] = npc

    if not QSF_Defs.writePlaced(placed) then
        QSF_refuse(player, npc.key, "WriteFailed")
        return
    end

    QSF.log(tostring(player:getUsername()) .. " placed npc " .. npc.key
        .. " at " .. npc.x .. "," .. npc.y .. "," .. npc.z)

    -- back through the file rather than straight into the table, so what is standing in
    -- the world is only ever what the files say.
    QSF_reloadAll()
end)

-- only ones the game placed. a hand-written npc is taken out of the file it was written
-- in, by whoever wrote it.
QSF_Commands.handlers.npcRemove = QSF_admin("remove an npc", function(player, args)
    local npc = args and QSF_Defs.npc(args.key) or nil
    if not npc or not npc.placed then return end

    local kept = {}
    for _, other in ipairs(QSF_Defs.npcList(true)) do
        if other.key ~= npc.key then kept[#kept + 1] = other end
    end

    if not QSF_Defs.writePlaced(kept) then
        QSF_refuse(player, npc.key, "WriteFailed")
        return
    end

    QSF.log(tostring(player:getUsername()) .. " removed npc " .. npc.key)

    QSF_reloadAll()
    QSF_Npcs.forget(npc.key)
end)

local function QSF_onClientCommand(module, command, player, args)
    if module ~= QSF.MODULE then return end

    local handler = QSF_Commands.handlers[command]
    if not handler then return end

    local ok, err = pcall(handler, player, args)
    if not ok then QSF.warn("command " .. tostring(command) .. " failed: " .. tostring(err)) end
end

Events.OnClientCommand.Add(QSF_onClientCommand)
