----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"
require "QSF_Defs"

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Npcs = QSF_Npcs or {}

local TABLE_NAME = "QSF_NpcState"
local ENSURE_MS = 2000

-- tiles. a body further than this from its own tile is put back.
local DRIFT = 1.5

-- a chunk's zombies arrive a moment after its squares do, and spawning into that gap
-- would leave two of them standing there.
local MISSES = 3

QSF_Npcs.state = QSF_Npcs.state or nil

-- runtime only. how many passes in a row each npc's tile was loaded with nobody on it.
local misses = {}
local warned = {}

-- runtime only. the zombie each npc was last seen as, so one thrown clear of the leash
-- can still be found and taken away instead of being left where it landed.
local lastBody = {}

-- runtime only. npcs that were killed in spite of everything, and are owed a tidy-up.
local died = {}

-- once per message: the pass runs every two seconds for as long as the server is up.
local function QSF_warnOnce(message)
    if warned[message] then return end
    warned[message] = true
    QSF.warn(message)
end

-- keyed by npc key. the id is kept for as long as the npc keeps its outfit, so one that
-- had to be stood back up comes back in the same clothes, and a file that failed to parse
-- for an afternoon does not re-dress everybody in it.
function QSF_Npcs.data()
    if not QSF_Npcs.state then
        QSF_Npcs.state = ModData.getOrCreate(TABLE_NAME)
    end
    return QSF_Npcs.state
end

function QSF_Npcs.idOf(key)
    local st = QSF_Npcs.data()[key]
    return st and st.id or nil
end

local function QSF_look(npc)
    return npc.outfit .. (npc.female and "/f" or "/m")
end

local function QSF_loaded(x, y, z)
    return getCell():getGridSquare(x, y, z) ~= nil
end

-- every live zombie carrying this id within the leash of the tile. the squares are a box
-- and the leash is a circle, so the corners are checked again by distance.
local function QSF_bodies(x, y, z, id)
    local found = {}
    if not id then return found end

    local cell = getCell()
    local home = { x = x, y = y, z = z }
    local reach = QSF.NPC_LEASH

    for dx = -reach, reach do
        for dy = -reach, reach do
            local square = cell:getGridSquare(x + dx, y + dy, z)
            local objects = square and square:getMovingObjects() or nil

            for i = 0, (objects and objects:size() or 0) - 1 do
                local object = objects:get(i)
                if instanceof(object, "IsoZombie") and not object:isDead()
                    and QSF_Rules.npcId(object) == id
                    and QSF_Rules.isNear(object:getX(), object:getY(), object:getZ(), home, reach) then
                    found[#found + 1] = object
                end
            end
        end
    end

    return found
end

-- clients are never told a zombie was deleted. they drop it themselves once the server
-- has stopped sending it, which takes a few seconds.
local function QSF_remove(zombie)
    zombie:removeFromWorld()
    zombie:removeFromSquare()
end

local function QSF_removeAll(x, y, z, id)
    for _, zombie in ipairs(QSF_bodies(x, y, z, id)) do
        QSF_remove(zombie)
    end
end

-- useless is the only one of these the engine sends to clients. the rest are set again
-- on each of them, and all of it is lost whenever the zombie is unloaded, so this runs on
-- every pass rather than once at spawn.
function QSF_Npcs.settle(zombie)
    zombie:setUseless(true)
    zombie:setNoTeeth(true)
    zombie:setTarget(nil)

    -- covers what never goes through a weapon: fire, and the front of a car.
    zombie:setInvulnerable(true)
end

-- the npc this zombie is the body of, if it is one.
function QSF_Npcs.npcOf(zombie)
    if not zombie or not QSF_Npcs.state then return nil end

    local id = QSF_Rules.npcId(zombie)

    for key, st in pairs(QSF_Npcs.state) do
        if st.id == id then
            local npc = QSF_Defs.npcs[key]
            if npc and QSF_Rules.isNear(zombie:getX(), zombie:getY(), zombie:getZ(), npc, QSF.NPC_LEASH) then
                return npc
            end
        end
    end

    return nil
end

-- the spawn call's own invulnerable argument is left false: it goes through setGodMod,
-- which is switched straight back off for anything that is not a player.
local function QSF_spawn(npc, st)
    local spawned = addZombiesInOutfit(npc.x, npc.y, npc.z, 1, npc.outfit, npc.female and 100 or 0,
        false, false, false, false, false, false, 1)

    local zombie = spawned and spawned:size() > 0 and spawned:get(0) or nil
    if not zombie then
        QSF_warnOnce("npc " .. npc.key .. ": could not be spawned at " .. npc.x .. "," .. npc.y .. "," .. npc.z)
        return false
    end

    if st.id then
        -- the roll it was first given, so the clothes are the ones it had before.
        zombie:dressInPersistentOutfitID(st.id)
    else
        st.id = QSF_Rules.npcId(zombie)
    end

    zombie:setForwardIsoDirection(IsoDirections[npc.facing])
    QSF_Npcs.settle(zombie)

    lastBody[npc.key] = zombie
    return true
end

-- the object is handed back to the engine when its zombie goes and comes round again as
-- somebody else, so the id is what says it is still ours.
local function QSF_stray(npc, st)
    local zombie = lastBody[npc.key]
    lastBody[npc.key] = nil

    if not zombie or zombie:isDead() or not zombie:getCurrentSquare() then return nil end
    if QSF_Rules.npcId(zombie) ~= st.id then return nil end

    return zombie
end

-- a body left behind when its npc moved or changed outfit. the tile may not be loaded
-- for hours, so it is written down and cleared up when somebody next goes there.
local function QSF_leave(st)
    st.left = st.left or {}
    st.left[#st.left + 1] = { x = st.x, y = st.y, z = st.z, id = st.id }
end

-- lines the saved state up with what the files say now. returns true when an id moved.
local function QSF_reconcile(data)
    local changed = false

    for key, npc in pairs(QSF_Defs.npcs) do
        local st = data[key]
        if not st then
            st = {}
            data[key] = st
        end

        local look = QSF_look(npc)

        if st.id and (st.x ~= npc.x or st.y ~= npc.y or st.z ~= npc.z or st.look ~= look) then
            QSF_leave(st)

            -- the wait is for a body that might still be loading. this one was moved on
            -- purpose and there is nothing to wait for.
            misses[key] = MISSES

            -- a new outfit is a new roll. a new tile keeps the old one.
            if st.look ~= look then
                st.id = nil
                changed = true
            end
        end

        st.x, st.y, st.z, st.look = npc.x, npc.y, npc.z, look
    end

    return changed
end

local function QSF_cleanUp(data)
    for key, st in pairs(data) do
        if st.left then
            local kept = {}
            for _, spot in ipairs(st.left) do
                if QSF_loaded(spot.x, spot.y, spot.z) then
                    QSF_removeAll(spot.x, spot.y, spot.z, spot.id)
                else
                    kept[#kept + 1] = spot
                end
            end
            st.left = #kept > 0 and kept or nil
        end

        -- gone from the files but not forgotten: the id waits for it to come back.
        if not QSF_Defs.npcs[key] and st.id and st.x and QSF_loaded(st.x, st.y, st.z) then
            QSF_removeAll(st.x, st.y, st.z, st.id)

            -- taken away on purpose, so if the npc is written back in it is stood
            -- straight back up.
            misses[key] = MISSES
        end
    end
end

local function QSF_nearest(bodies, npc)
    local best, bestDist = nil, nil

    for _, zombie in ipairs(bodies) do
        local dx = zombie:getX() - (npc.x + 0.5)
        local dy = zombie:getY() - (npc.y + 0.5)
        local dist = dx * dx + dy * dy

        if not bestDist or dist < bestDist then
            best, bestDist = zombie, dist
        end
    end

    return best, bestDist
end

-- only ever after an npc died, which nothing should be able to cause. a corpse carries
-- the outfit's loot, and one that comes back every few seconds would be a tap.
local function QSF_clearCorpse(npc)
    local cell = getCell()

    for dx = -QSF.NPC_LEASH, QSF.NPC_LEASH do
        for dy = -QSF.NPC_LEASH, QSF.NPC_LEASH do
            local square = cell:getGridSquare(npc.x + dx, npc.y + dy, npc.z)
            local corpses = square and square:getDeadBodys() or nil

            -- backwards, since taking one out shuffles the rest down.
            for i = (corpses and corpses:size() or 0) - 1, 0, -1 do
                local corpse = corpses:get(i)
                if corpse:getOutfitName() == npc.outfit then
                    square:removeCorpse(corpse, false)
                end
            end
        end
    end
end

-- returns true when the npc was given an id it did not have before.
local function QSF_ensureOne(npc, st)
    if died[npc.key] then
        died[npc.key] = nil
        QSF_clearCorpse(npc)
    end

    local bodies = QSF_bodies(npc.x, npc.y, npc.z, st.id)
    local keep, dist = QSF_nearest(bodies, npc)

    -- two can only be an ordinary zombie that rolled the same id, or a body that loaded
    -- late. either way there is one npc.
    for _, zombie in ipairs(bodies) do
        if zombie ~= keep then QSF_remove(zombie) end
    end

    if keep then
        misses[npc.key] = 0

        if dist > DRIFT * DRIFT then
            -- a zombie's position belongs to whichever client is nearest it, so moving it
            -- from here would only be overruled. a fresh one on the tile is not.
            QSF_remove(keep)
            QSF_spawn(npc, st)
        else
            QSF_Npcs.settle(keep)
            lastBody[npc.key] = keep
        end

        return false
    end

    local hadId = st.id ~= nil
    misses[npc.key] = (misses[npc.key] or 0) + 1

    -- seen a moment ago and now past the leash: a car, most likely. nothing to wait for.
    local stray = QSF_stray(npc, st)
    if stray then
        QSF_remove(stray)
        misses[npc.key] = MISSES
    end

    -- one that has never existed has nothing to wait for either.
    if hadId and misses[npc.key] < MISSES then return false end

    misses[npc.key] = 0
    return QSF_spawn(npc, st) and not hadId
end

-- for an npc an admin took away on purpose. one that merely dropped out of the files
-- keeps its id in case it comes back; this one is not coming back.
function QSF_Npcs.forget(key)
    local data = QSF_Npcs.data()
    local st = data[key]
    if not st then return end

    -- somewhere nobody is, the body cannot be reached yet. the record stays so the
    -- clean-up pass still knows what to take away when somebody gets there.
    if st.id and st.x and not QSF_loaded(st.x, st.y, st.z) then return end

    if st.id and st.x then QSF_removeAll(st.x, st.y, st.z, st.id) end

    data[key] = nil
    misses[key] = nil
    lastBody[key] = nil
end

function QSF_Npcs.wireIds()
    local ids = {}
    for key, st in pairs(QSF_Npcs.data()) do
        if st.id and QSF_Defs.npcs[key] then ids[key] = st.id end
    end
    return ids
end

function QSF_Npcs.sendIds(player)
    QSF_Net.toClient(player, "npcIds", { ids = QSF_Npcs.wireIds() })
end

function QSF_Npcs.ensure()
    -- before the files are read every npc looks like one that was deleted.
    if not QSF_Defs.loaded then return end

    local data = QSF_Npcs.data()
    local changed = QSF_reconcile(data)

    QSF_cleanUp(data)

    for key, npc in pairs(QSF_Defs.npcs) do
        if QSF_loaded(npc.x, npc.y, npc.z) then
            if QSF_ensureOne(npc, data[key]) then changed = true end
        else
            misses[key] = nil
        end
    end

    -- a client cannot tell an npc from a zombie until it has the id.
    if changed then QSF_Net.toAll("npcIds", { ids = QSF_Npcs.wireIds() }) end
end

local lastEnsure = 0

local function QSF_tick()
    local now = getTimestampMs()
    if now - lastEnsure < ENSURE_MS then return end
    lastEnsure = now

    local ok, err = pcall(QSF_Npcs.ensure)
    if not ok then QSF_warnOnce("npc pass failed: " .. tostring(err)) end
end

-- the real clock paces it. EveryOneMinute is only here in case a build's server does not
-- fire OnTick, and on its own would sprint whenever everyone slept.
Events.OnTick.Add(QSF_tick)
Events.EveryOneMinute.Add(QSF_tick)

-- fired before the engine looks at its own avoid flag, so the swing is thrown away whole:
-- no damage, and none of the stagger an invulnerable zombie would still be given.
local function QSF_onHitZombie(zombie)
    if QSF_Npcs.npcOf(zombie) then zombie:setAvoidDamage(true) end
end

Events.OnHitZombie.Add(QSF_onHitZombie)

-- nothing is meant to get this far. if something does, the next pass stands a new one up
-- without waiting, and takes the old one's corpse away.
local function QSF_onZombieDead(zombie)
    local npc = QSF_Npcs.npcOf(zombie)
    if not npc then return end

    QSF.warn("npc " .. npc.key .. " was killed and will be replaced")

    died[npc.key] = true
    misses[npc.key] = MISSES
    lastBody[npc.key] = nil
end

Events.OnZombieDead.Add(QSF_onZombieDead)

Events.OnInitGlobalModData.Add(function()
    QSF_Npcs.data()
end)
