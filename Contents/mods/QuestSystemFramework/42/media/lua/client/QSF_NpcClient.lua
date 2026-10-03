----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_ClientState"

QSF = QSF or {}
QSF_NpcClient = QSF_NpcClient or {}

-- the anim variable media/AnimSets/zombie/idle/QSF_NpcIdle.xml is gated on.
local FLAG = "QSF_NPC"

-- a prefix no sound bank has, so the engine finds nothing to moan with.
local SILENT = "QSF_Silent"

local VOICES = {
    "MaleZombieVoiceA", "MaleZombieVoiceB", "MaleZombieVoiceC",
    "FemaleZombieVoiceA", "FemaleZombieVoiceB", "FemaleZombieVoiceC",
}

-- id to the npcs carrying it. a list, because two npcs in the same outfit can roll the
-- same one and only their tiles tell them apart.
local byId = {}
local hasNpcs = false
local revision = -1

-- this client's own note of which zombies it has dressed up, keyed by the zombie. the
-- engine reuses zombie objects, and one handed back as an ordinary zombie must not go on
-- standing there with its teeth out.
local dressed = {}
local hasDressed = false

-- the zombie each npc was last seen as, for whatever needs to find one on screen.
QSF_NpcClient.bodies = QSF_NpcClient.bodies or {}

local function QSF_reindex()
    byId = {}
    hasNpcs = false

    for key, npc in pairs(QSF_ClientState.npcs) do
        local id = QSF_ClientState.npcIds[key]
        if id then
            byId[id] = byId[id] or {}
            table.insert(byId[id], npc)
            hasNpcs = true
        end
    end

    for key in pairs(QSF_NpcClient.bodies) do
        if not QSF_ClientState.npcs[key] then QSF_NpcClient.bodies[key] = nil end
    end
end

local function QSF_match(zombie)
    local list = byId[QSF_Rules.npcId(zombie)]
    if not list then return nil end

    local x, y, z = zombie:getX(), zombie:getY(), zombie:getZ()
    for _, npc in ipairs(list) do
        if QSF_Rules.isNear(x, y, z, npc, QSF.NPC_LEASH) then return npc end
    end

    return nil
end

local function QSF_skinName(npc)
    return (npc.female and "FemaleBody0" or "MaleBody0") .. tostring(npc.skin or 1)
end

-- the engine puts the rot back whenever it rebuilds the zombie, so this is what says the
-- dressing-up has to be done again.
local function QSF_looksHuman(zombie)
    local skin = zombie:getHumanVisual():getSkinTexture()
    if not skin then return false end
    return skin:find("^MaleBody0%d$") ~= nil or skin:find("^FemaleBody0%d$") ~= nil
end

-- the clothes are the engine's own pick for this outfit id and are left alone. what goes
-- is everything that says the wearer is dead.
local function QSF_humanise(zombie, npc)
    local visual = zombie:getHumanVisual()

    visual:setSkinTextureName(QSF_skinName(npc))
    visual:removeBlood()
    visual:removeDirt()

    -- bites, bullet holes and missing jaws are body visuals, not part of the skin.
    local wounds = {}
    local bodyVisuals = visual:getBodyVisuals()
    for i = 0, bodyVisuals:size() - 1 do
        local itemType = bodyVisuals:get(i):getItemType()
        if itemType and itemType:find("ZedDmg", 1, true) then wounds[#wounds + 1] = itemType end
    end
    for _, itemType in ipairs(wounds) do
        visual:removeBodyVisualFromItemType(itemType)
    end

    local parts = BloodBodyPartType.MAX:index()
    local itemVisuals = zombie:getItemVisuals()
    for i = 0, itemVisuals:size() - 1 do
        local item = itemVisuals:get(i)
        for index = 0, parts - 1 do
            local part = BloodBodyPartType.FromIndex(index)
            item:removeHole(index)
            item:setBlood(part, 0)
            item:setDirt(part, 0)
        end
    end

    zombie:resetModelNextFrame()

    zombie:setVariable(FLAG, true)
    zombie:getDescriptor():setVoicePrefix(SILENT)
    zombie:getEmitter():stopAll()
end

-- none of this reaches the server or the next client along; each one holds its own copy
-- of the zombie still. useless alone would do it, but only until the object is reused.
local function QSF_pacify(zombie, npc)
    zombie:setUseless(true)
    zombie:setNoTeeth(true)
    zombie:setTarget(nil)
    zombie:setEatBodyTarget(nil, false)

    -- covers what never goes through a weapon: fire, and the front of a car.
    zombie:setInvulnerable(true)

    -- a noise still turns its head, and the turn is a zombie's.
    if zombie:getActionStateName() == "turnalerted" then
        zombie:changeState(ZombieIdleState.instance())
    end

    local facing = IsoDirections[npc.facing]
    if facing and zombie:getDir() ~= facing then
        zombie:setForwardIsoDirection(facing)
    end

    -- the prefix covers most of it. a voice already playing when the zombie arrived
    -- carries on regardless.
    local emitter = zombie:getEmitter()
    for _, voice in ipairs(VOICES) do
        emitter:stopSoundByName(voice)
    end
end

-- back to an ordinary zombie. its looks are the engine's to rebuild.
local function QSF_release(zombie)
    dressed[zombie] = nil
    -- the game's lua has no next(). this is its own way of asking.
    hasDressed = not table.isempty(dressed)

    zombie:setVariable(FLAG, false)
    zombie:setUseless(false)
    zombie:setNoTeeth(false)
    zombie:setInvulnerable(false)
end

local function QSF_onZombieUpdate(zombie)
    if revision ~= QSF_ClientState.revision then
        revision = QSF_ClientState.revision
        QSF_reindex()
    end

    -- the common case by a long way: a server with no npcs pays one comparison a zombie.
    if not hasNpcs and not hasDressed then return end

    local npc = hasNpcs and QSF_match(zombie) or nil

    if not npc then
        if hasDressed and dressed[zombie] then QSF_release(zombie) end
        return
    end

    if dressed[zombie] ~= npc.key or not QSF_looksHuman(zombie) then
        QSF_humanise(zombie, npc)
        dressed[zombie] = npc.key
        hasDressed = true
    end

    QSF_pacify(zombie, npc)
    QSF_NpcClient.bodies[npc.key] = zombie
end

-- whether this zombie is one of ours, for anything else that handles zombies.
function QSF_NpcClient.npcOf(zombie)
    local key = zombie and dressed[zombie] or nil
    return key and QSF_ClientState.npcs[key] or nil
end

-- the body is only trusted while it is still where an npc should be: the object outlives
-- the npc, sits in the engine's pool with its last position, and comes back as something
-- else.
function QSF_NpcClient.bodyOf(key)
    local zombie = QSF_NpcClient.bodies[key]
    if not zombie or dressed[zombie] ~= key then return nil end

    local npc = QSF_ClientState.npcs[key]
    if not npc or not zombie:getCurrentSquare() then return nil end
    if not QSF_Rules.isNear(zombie:getX(), zombie:getY(), zombie:getZ(), npc, QSF.NPC_LEASH) then return nil end

    return zombie
end

-- gold "?" beats gold "!" beats grey "?": something to hand in matters more than
-- something new, and either matters more than a reminder. nil is nothing to say.
function QSF_NpcClient.status(npcKey, player)
    local available, progress = false, false
    local counts = QSF_ClientState.counts()

    for _, def in ipairs(QSF_Rules.npcQuests(npcKey, QSF_ClientState.ordered)) do
        local rec = QSF_ClientState.record(def.key)

        if rec and rec.status == "active" then
            if QSF_Rules.isComplete(def, rec, counts) then return "turnin" end
            progress = true
        elseif QSF_Rules.canAccept(def, rec, player, QSF_ClientState.state) then
            -- the same test the log greys a row with, so a locked or hidden quest
            -- raises no marker.
            available = true
        end
    end

    if available then return "available" end
    if progress then return "progress" end
    return nil
end

Events.OnZombieUpdate.Add(QSF_onZombieUpdate)

-- fired before the engine looks at its own avoid flag, so the swing is thrown away whole:
-- no damage, and none of the stagger an invulnerable zombie would still be given. the
-- swing is worked out on the machine that made it, which is why this is here as well as
-- on the server.
local function QSF_onHitZombie(zombie)
    if QSF_NpcClient.npcOf(zombie) then zombie:setAvoidDamage(true) end
end

Events.OnHitZombie.Add(QSF_onHitZombie)
