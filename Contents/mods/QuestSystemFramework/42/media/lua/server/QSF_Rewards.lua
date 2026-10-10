----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"

if not QSF.isAuthority() then return end

QSF_Rewards = QSF_Rewards or {}

-- one at a time rather than AddItems, so a container that fills partway through reports
-- how far it got instead of returning a short list nobody reads.
local function QSF_giveItem(player, fullType, count)
    local inventory = player:getInventory()
    local given = 0

    for _ = 1, count do
        local item = inventory:AddItem(fullType)
        if not item then break end

        if isServer() then
            sendAddItemToContainer(inventory, item)
        end

        given = given + 1
    end

    return given
end

local function QSF_giveEntry(player, entry, def)
    local given = QSF_giveItem(player, entry.item, entry.count)

    if given < entry.count then
        QSF.warn(tostring(player:getUsername()) .. ": only " .. given .. " of " .. entry.count
            .. " " .. entry.item .. " could be given for " .. def.key)
    end
end

-- what a random pool comes up as this time: as many of its options as it rolls, each a
-- different one, and each drawn by its weight from whatever is still in. the server's own
-- dice, so there is nothing for a client to say about it.
function QSF_Rewards.roll(pool)
    local drawn = {}
    if not pool then return drawn end

    local left, total = {}, 0
    for i, option in ipairs(pool.options) do
        left[i] = option
        total = total + (option.weight or 1)
    end

    for _ = 1, math.min(pool.rolls or 1, #left) do
        -- a whole number from nothing up to one short of the total, which lands in
        -- exactly one option's share of it.
        local at = ZombRand(total)

        for i, option in ipairs(left) do
            at = at - (option.weight or 1)

            if at < 0 then
                drawn[#drawn + 1] = { item = option.item, count = option.count }
                total = total - (option.weight or 1)
                table.remove(left, i)
                break
            end
        end
    end

    return drawn
end

-- pick is the ordinal the player chose at turn-in, and is only ever read back through
-- QSF_Rules.pickedReward, so it can only name an option this quest actually offers.
-- returns what the random pool came up as, for whoever tells the player.
function QSF_Rewards.grant(player, def, pick)
    if not player or not def then return {} end

    local rewards = def.rewards or {}

    for _, entry in ipairs(rewards.items or {}) do
        QSF_giveEntry(player, entry, def)
    end

    local chosen = QSF_Rules.pickedReward(def, pick)
    if chosen then QSF_giveEntry(player, chosen, def) end

    local rolled = QSF_Rewards.roll(rewards.random)
    for _, entry in ipairs(rolled) do
        QSF_giveEntry(player, entry, def)
    end

    for perkName, amount in pairs(rewards.xp or {}) do
        local perk = QSF_Rules.perk(perkName)
        if perk then player:getXp():AddXP(perk, amount) end
    end

    return rolled
end
