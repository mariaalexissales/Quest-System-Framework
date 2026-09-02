----------
--ESTRAL--
----------

require "QSF_Panel"

-- a key is the entry point that works before any sidebar art exists, and it stays as the
-- one players can rebind if another mod takes the icon slot.

local QSF_KEY = Keyboard.KEY_J

keyBinding = keyBinding or {}
table.insert(keyBinding, { value = "[Quests]" })
table.insert(keyBinding, { value = "Toggle Quest Log", key = QSF_KEY })

local function QSF_onKeyPressed(key)
    if key ~= getCore():getKey("Toggle Quest Log") then return end

    local player = getSpecificPlayer(0)
    if not player or player:isDead() then return end

    QSF.togglePanel(player)
end

Events.OnKeyPressed.Add(QSF_onKeyPressed)
