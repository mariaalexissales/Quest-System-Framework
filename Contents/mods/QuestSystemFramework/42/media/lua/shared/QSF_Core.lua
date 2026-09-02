----------
--ESTRAL--
----------

QSF = QSF or {}

QSF.MODULE = "QSF"
QSF.SCHEMA_V = 1

-- admins drop their .json here, under Zomboid/Lua/. picked over the mod folder because
-- Steam overwrites a workshop folder on every update and would wipe their quests.
QSF.DIR = "QuestFramework"

QSF.Config = QSF.Config or {
    -- OnZombieDead hands us no killer, only zombie:getAttackedBy(), and whether that
    -- survives the trip on a dedicated server is unverified. flip this if the server log
    -- shows a nil attacker and the client reports its own kills instead - cheaper to
    -- cheat, so it stays off until a server owner needs it.
    clientKillReporting = false,

    -- registering our own Region zones would make getSquareRegion() return "Ekron", but
    -- Region zones feed vanilla spawn and metazone logic, so injecting five of them can
    -- move zombie and loot distribution in ways nobody would trace back to a quest mod.
    -- off by default; we test our own boxes instead.
    registerTownZones = false,
}

-- the one place that decides whether this process owns quest state. server/ lua is loaded
-- on multiplayer clients too, so every server file gates on this rather than on isServer(),
-- which would be false in singleplayer and take the whole mod down with it.
function QSF.isAuthority()
    return not (isClient() and not isServer())
end

function QSF.hasRemoteServer()
    return isClient() and not isServer()
end

-- singleplayer has no access levels, so the local player is always the admin there.
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

-- getText on a missing key returns the key itself, which would put raw
-- MapLabel_Ekron strings in the UI. getTextOrNull lets us fall back to something legible.
function QSF.text(key, fallback)
    local value = getTextOrNull(key)
    if value and value ~= "" then return value end
    return fallback or key
end
