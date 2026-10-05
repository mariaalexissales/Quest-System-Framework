----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_State"
require "QSF_Kills"

if not QSF.isAuthority() then return end

-- One More Horde: Horde Night. shared files load before any server file, so its table is
-- either here by now or the mod is off, and the horde objectives just never move.
if not OneMoreHordeExtensions then return end

QSF_Horde = QSF_Horde or {}

-- it knows a player by username in multiplayer and by singleplayer:<slot> on your own, so
-- ask it who is who rather than guess. its persistence loads after this file does.
function QSF_Horde.username(id)
    if OneMoreHordePersistence then
        for _, player in ipairs(QSF_State.players()) do
            if OneMoreHordePersistence.getPlayerIdentityId(player) == id then
                return player:getUsername()
            end
        end
    end

    return id
end

-- a night only counts for the ones it would reward: there, alive, and not written off as
-- a casualty or a vigilante.
local function QSF_onFinished(snapshot)
    if snapshot.outcome ~= "survived" then return end

    for id in pairs(snapshot.rewardParticipants or {}) do
        QSF_Kills.bump(QSF_Horde.username(id), "horde")
    end
end

-- called once per kill it credits. killCount is the running total for the night, not a step.
local function QSF_onKill(snapshot)
    QSF_Kills.bump(QSF_Horde.username(snapshot.participantId), "hordeKill")
end

-- it calls these bare, and a throw from onFinished lands before it has closed the night,
-- which it would then finish and score a second time.
local function QSF_guard(hook)
    return function(snapshot)
        local ok, err = pcall(hook, snapshot)
        if not ok then QSF.warn("horde hook failed: " .. tostring(err)) end
    end
end

local ok, err = OneMoreHordeExtensions.register({
    id = "QuestSystemFramework",
    apiVersion = 3,
    version = "1",
    capabilities = { hordeEvents = true },
    eventHooks = {
        onFinished = QSF_guard(QSF_onFinished),
        onKill = QSF_guard(QSF_onKill),
    },
})

if ok then
    QSF.log("One More Horde found, horde objectives are live")
else
    QSF.warn("One More Horde turned the quest hooks down: " .. tostring(err))
end
