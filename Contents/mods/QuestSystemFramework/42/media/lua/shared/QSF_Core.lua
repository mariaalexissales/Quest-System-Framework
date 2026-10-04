----------
--ESTRAL--
----------

QSF = QSF or {}

QSF.MODULE = "QSF"
QSF.SCHEMA_V = 1

-- under Zomboid/Lua/, not the mod folder: Steam overwrites that on every workshop update.
QSF.DIR = "QuestFramework"

-- the one file in that folder the mod writes for itself, so placing an npc in game never
-- rewrites a file somebody typed out by hand and loses their comments.
QSF.NPC_FILE = "npcs_placed.json"

-- tiles. how close a player has to stand to a giver to take a quest or hand one in.
QSF.NPC_REACH = 3

-- tiles. how far from its own tile a zombie can be and still be taken for the npc. the
-- server looks this far for the body and a client dresses it up this far out, so the two
-- cannot disagree about who it is.
QSF.NPC_LEASH = 3

-- god mode is what keeps an npc alive, and the game only honours it on a server or with
-- debug mode on. in an ordinary singleplayer game it is refused outright. so an npc is
-- also kept at more health than any one blow takes, topped up before the next can land.
QSF.NPC_HEALTH = 1000

QSF.Config = QSF.Config or {
    -- flip this if a dedicated server logs a nil attacker on the kill path. the client
    -- reports its own kills instead, which is clamped but cheaper to cheat.
    clientKillReporting = false,

    -- Region zones feed vanilla spawn and metazone logic, so registering our own can move
    -- zombie and loot distribution. off by default; QSF_Location tests the boxes directly.
    registerTownZones = false,
}

-- server/ lua loads on multiplayer clients too, and isServer() is false in singleplayer.
function QSF.isAuthority()
    return not (isClient() and not isServer())
end

function QSF.hasRemoteServer()
    return isClient() and not isServer()
end

function QSF.isAdmin(player)
    if not QSF.hasRemoteServer() then return true end
    if not player then return false end

    local level = player:getAccessLevel()
    return level == "Admin" or level == "GM" or level == "Moderator"
end

function QSF.log(message)
    print("[QSF] " .. tostring(message))
end

function QSF.warn(message)
    print("[QSF] WARN: " .. tostring(message))
end

-- getText on a missing key returns the key, which would print MapLabel_Ekron in the UI.
function QSF.text(key, fallback)
    local value = getTextOrNull(key)
    if value and value ~= "" then return value end
    return fallback or key
end
