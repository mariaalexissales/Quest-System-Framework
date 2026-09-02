----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Location"
require "QSF_Rules"
require "QSF_State"

-- crediting zombie kills to whoever earned them.
--
-- OnZombieDead hands over the zombie and nothing else - there is no OnKillZombie and no
-- killer argument - so the attacker comes from zombie:getAttackedBy(), which is nil for
-- fire and falls. whether that survives on a dedicated server is the one assumption in
-- this mod that source alone cannot settle, so QSF.Config.clientKillReporting exists as
-- the way out if a server log shows a nil attacker.

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Kills = QSF_Kills or {}

-- a modified client can claim whatever it likes, so the reported path is clamped and
-- noisy rather than trusted. this is the honest ceiling for a client-detected event.
local MAX_PER_FLUSH = 40

-- the kill is credited where the zombie died, not where the player stands. that is what
-- "kills in Ekron" means, and it stays right when somebody shoots across a boundary.
function QSF_Kills.credit(username, x, y, z)
    if not username then return end

    local quests = QSF_State.forPlayer(username)
    if not quests then return end

    local defs = QSF_Defs and QSF_Defs.all or {}

    for key, rec in pairs(quests) do
        if rec.status == "active" then
            local def = defs[key]

            if def then
                for i, obj in ipairs(def.objectives) do
                    if obj.type == "kill" and QSF_Location.matchXY(x, y, z, obj.location) then
                        local justFinished = QSF_State.addKill(username, key, i, obj.count)
                        -- a counter reaching its target has to reach the ui immediately,
                        -- so completion skips the send throttle.
                        QSF_State.markDirty(username, key, justFinished)
                    end
                end
            end
        end
    end
end

local function QSF_onZombieDead(zombie)
    if QSF.Config.clientKillReporting then return end
    if not zombie then return end

    local ok, attacker = pcall(function() return zombie:getAttackedBy() end)
    if not ok or not attacker then return end

    local username
    local okName = pcall(function() username = attacker:getUsername() end)
    -- a username is the cheapest discriminator between a player and anything else that
    -- can land a killing blow.
    if not okName or not username then return end

    -- the square can already be gone while the zombie is torn down, but the float
    -- coordinates survive, so the location test is written against those.
    QSF_Kills.credit(username, zombie:getX(), zombie:getY(), zombie:getZ())
end

Events.OnZombieDead.Add(QSF_onZombieDead)

-- the fallback. the client is certain who swung, but cannot be trusted about how often,
-- so the server re-derives the location from the player it can see and throws the
-- client's own claim about where it happened away.
function QSF_Kills.onReported(player, args)
    if not QSF.Config.clientKillReporting then return end
    if not player or not args then return end

    local count = tonumber(args.n) or 0
    if count < 1 then return end

    if count > MAX_PER_FLUSH then
        QSF.warn(tostring(player:getUsername()) .. " reported " .. count
            .. " kills in one flush, clamped to " .. MAX_PER_FLUSH)
        count = MAX_PER_FLUSH
    end

    local username = player:getUsername()
    for _ = 1, count do
        QSF_Kills.credit(username, player:getX(), player:getY(), player:getZ())
    end
end
