----------
--ESTRAL--
----------

QSF = QSF or {}

QSF.MODULE = "QSF"
QSF.SCHEMA_V = 1

-- under Zomboid/Lua/, not the mod folder: Steam overwrites that on every workshop update.
QSF.DIR = "QuestFramework"

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
