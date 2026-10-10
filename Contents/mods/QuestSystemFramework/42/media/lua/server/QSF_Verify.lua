----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Net"
require "QSF_Rules"
require "QSF_State"
require "QSF_Rewards"

if not QSF.isAuthority() then return end

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

-- one at a time, so an inventory that turns out short says how far it got. returns how
-- many went.
function QSF_Verify.take(player, item, count)
    local inventory = player:getInventory()
    local taken = 0

    for _ = 1, count do
        local removed = inventory:RemoveOneOf(item, true)
        if not removed then break end

        if isServer() then
            sendRemoveItemFromContainer(inventory, removed)
        end

        taken = taken + 1
    end

    return taken
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

    for item, need in pairs(wanted) do
        if QSF_Verify.take(player, item, need) < need then
            QSF.warn(tostring(player:getUsername()) .. ": could not take " .. item
                .. " for " .. def.key .. ", some may have been taken already")
        end
    end

    return true
end

-- the only path that completes a quest and pays it out. whatever the client claimed about
-- its own progress is ignored and re-derived here.
function QSF_Verify.claim(player, key, pick)
    if not player then return false, "Unknown" end

    local username = player:getUsername()
    local def = QSF_Defs.get(key)
    if not def then return false, "Unknown" end

    local rec = QSF_State.record(username, key)
    if not rec or rec.status ~= "active" then return false, "NotActive" end

    if rec.sig and rec.sig ~= def.sig then
        return false, "Changed"
    end

    -- here rather than in the command, so there is no way to be paid that skips it.
    if not QSF_Rules.atGiver(def, QSF_Defs.npcs, player) then
        return false, "TooFar"
    end

    -- before anything is taken, so a stale or crafted pick cannot cost the player their
    -- items and leave the quest unpaid.
    if def.rewards and def.rewards.choice then
        local chosen, reason = QSF_Rules.pickedReward(def, pick)
        if not chosen then return false, reason end
    end

    local counts = QSF_Verify.countItems(player, def)
    if not QSF_Rules.isComplete(def, rec, counts) then
        return false, "Incomplete"
    end

    if not QSF_consume(player, def, counts) then
        return false, "Incomplete"
    end

    QSF_Rewards.grant(player, def, pick)
    QSF_State.complete(username, key)
    QSF_State.push(username, key)

    -- from here rather than from the command, so the sweep below says so as well.
    QSF_Net.toClient(player, "toast", { kind = "completed", key = key })

    QSF.log(username .. " completed " .. key)
    return true

end

-- covers a client that crashed or never had the mod, and runs the same check claim does.
local function QSF_sweep()
    if not QSF_Defs or not QSF_Defs.loaded then return end

    for _, player in ipairs(QSF_State.players()) do
        if player:getUsername() then
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
