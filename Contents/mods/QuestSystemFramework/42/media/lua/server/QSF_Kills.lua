----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Location"
require "QSF_Rules"
require "QSF_State"

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Kills = QSF_Kills or {}

local MAX_PER_FLUSH = 40

-- credited where the zombie died rather than where the player stands, so a shot across a
-- boundary still counts for the place it was aimed at.
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
                        -- a counter hitting its target skips the send throttle.
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

    -- OnZombieDead passes the zombie and nothing else, so the killer comes off the zombie.
    -- nil for fire and falls, and getUsername is nil for anything that is not a player.
    local attacker = zombie:getAttackedBy()
    if not attacker then return end

    local username = attacker:getUsername()
    if not username then return end

    -- the square is already gone while the zombie is torn down; the coordinates are not.
    QSF_Kills.credit(username, zombie:getX(), zombie:getY(), zombie:getZ())
end

Events.OnZombieDead.Add(QSF_onZombieDead)

-- the client knows who swung but not how honestly, so the server re-derives the location
-- from the player it can see and discards whatever the client claimed about it.
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
