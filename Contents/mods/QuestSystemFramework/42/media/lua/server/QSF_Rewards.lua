----------
--ESTRAL--
----------

require "QSF_Core"

if not QSF.isAuthority() then return end

QSF = QSF or {}
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
        local perk = PerkFactory.Perks.FromString(perkName)
        if perk then player:getXp():AddXP(perk, amount) end
    end
end
