----------
--ESTRAL--
----------

require "QSF_Panel"

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
