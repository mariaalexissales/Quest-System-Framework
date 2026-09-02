----------
--ESTRAL--
----------

require "QSF_Core"

-- paying a quest out. server side only, and in multiplayer every add has to be announced
-- with sendAddItemToContainer or the client never sees the item appear.

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Rewards = QSF_Rewards or {}

-- AddItems is one call for a stack, but it returns a list and a partial failure is
-- easier to reason about one item at a time, so single items go through AddItem.
local function QSF_giveItem(player, fullType, count)
    local inventory = player:getInventory()
    local given = 0

    for _ = 1, count do
        local ok, item = pcall(function() return inventory:AddItem(fullType) end)
        if not ok or not item then break end

        if isServer() then
            pcall(function() sendAddItemToContainer(inventory, item) end)
        end

        given = given + 1
    end

    return given
end

function QSF_Rewards.grant(player, def)
    if not player or not def then return end

    local rewards = def.rewards or {}

    for _, entry in ipairs(rewards.items or {}) do
        local given = QSF_giveItem(player, entry.item, entry.count)

        if given < entry.count then
            QSF.warn(tostring(player:getUsername()) .. ": only " .. given .. " of " .. entry.count
                .. " " .. entry.item .. " could be given for " .. def.key)
        end
    end

    for perkName, amount in pairs(rewards.xp or {}) do
        pcall(function()
            local perk = PerkFactory.Perks.FromString(perkName)
            if perk then player:getXp():AddXP(perk, amount) end
        end)
    end
end
