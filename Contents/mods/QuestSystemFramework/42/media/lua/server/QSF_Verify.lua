----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_State"
require "QSF_Rewards"

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Verify = QSF_Verify or {}

-- Recurse, or everything in a bag goes uncounted.
function QSF_Verify.countItems(player, def)
    local counts = {}
    local inventory = player:getInventory()

    for _, obj in ipairs(def.objectives) do
        if obj.type == "collect" and counts[obj.item] == nil then
            counts[obj.item] = inventory:getItemCountRecurse(obj.item)
        end
    end

    return counts
end

-- the whole set is checked before anything is removed, so a short player keeps the lot.
local function QSF_consume(player, def, counts)
    local wanted = {}

    for _, obj in ipairs(def.objectives) do
        if obj.type == "collect" and obj.consume then
            wanted[obj.item] = (wanted[obj.item] or 0) + obj.count
        end
    end

    for item, need in pairs(wanted) do
        if (counts[item] or 0) < need then return false end
    end

    local inventory = player:getInventory()
    for item, need in pairs(wanted) do
        for _ = 1, need do
            local removed = inventory:RemoveOneOf(item, true)
            if not removed then
                QSF.warn(tostring(player:getUsername()) .. ": could not take " .. item
                    .. " for " .. def.key .. ", some may have been taken already")
                break
            end
            if isServer() then
                sendRemoveItemFromContainer(inventory, removed)
            end
        end
    end

    return true
end

-- the only path that completes a quest and pays it out. whatever the client claimed about
-- its own progress is ignored and re-derived here.
function QSF_Verify.claim(player, key)
    if not player then return false, "Unknown" end

    local username = player:getUsername()
    local def = QSF_Defs.get(key)
    if not def then return false, "Unknown" end

    local rec = QSF_State.record(username, key)
    if not rec or rec.status ~= "active" then return false, "NotActive" end

    if rec.sig and rec.sig ~= def.sig then
        return false, "Changed"
    end

    local counts = QSF_Verify.countItems(player, def)
    if not QSF_Rules.isComplete(def, rec, counts) then
        return false, "Incomplete"
    end

    if not QSF_consume(player, def, counts) then
        return false, "Incomplete"
    end

    QSF_Rewards.grant(player, def)
    QSF_State.complete(username, key)
    QSF_State.push(username, key)

    QSF.log(username .. " completed " .. key)
    return true
end

-- covers a client that crashed or never had the mod, and runs the same check claim does.
local function QSF_sweep()
    if not QSF_Defs or not QSF_Defs.loaded then return end

    local players = isServer() and getOnlinePlayers() or nil
    local count = players and players:size() or 1

    for i = 1, count do
        local player = players and players:get(i - 1) or getPlayer()

        if player and player:getUsername() then
            local quests = QSF_State.forPlayer(player:getUsername())

            for key, rec in pairs(quests or {}) do
                local def = rec.status == "active" and QSF_Defs.get(key) or nil
                if def and def.autoComplete then
                    local counts = QSF_Verify.countItems(player, def)
                    if QSF_Rules.isComplete(def, rec, counts) then
                        QSF_Verify.claim(player, key)
                    end
                end
            end
        end
    end
end

Events.EveryTenMinutes.Add(QSF_sweep)
