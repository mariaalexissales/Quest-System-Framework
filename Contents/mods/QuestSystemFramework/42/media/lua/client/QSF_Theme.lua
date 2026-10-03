----------
--ESTRAL--
----------

require "QSF_Rules"

QSF = QSF or {}
QSF_Theme = QSF_Theme or {}

-- NeatUI's end caps take a tint and the body does not, so state is carried by tinting
-- the caps and filling the body behind them.
QSF_Theme.STATES = {
    disabled = { cap = { 0.45, 0.45, 0.45 }, alpha = 0.45, fill = nil,
                 text = { 0.42, 0.42, 0.42 } },
    normal   = { cap = { 0.72, 0.72, 0.72 }, alpha = 0.85, fill = { 1, 1, 1, 0.03 },
                 text = { 0.84, 0.84, 0.84 } },
    hover    = { cap = { 1.00, 1.00, 1.00 }, alpha = 1.00, fill = { 1, 1, 1, 0.10 },
                 text = { 1.00, 1.00, 1.00 } },
    pressed  = { cap = { 0.85, 0.85, 0.85 }, alpha = 1.00, fill = { 0, 0, 0, 0.25 },
                 text = { 0.92, 0.92, 0.92 } },
    selected = { cap = { 0.98, 0.82, 0.45 }, alpha = 1.00, fill = { 0.98, 0.82, 0.45, 0.12 },
                 text = { 1.00, 0.93, 0.74 } },
}

QSF_Theme.COL_BAR = { r = 0, g = 0, b = 0, a = 0.35 }
QSF_Theme.COL_FRAME = { r = 1, g = 1, b = 1, a = 0.09 }
QSF_Theme.COL_WELL = { r = 0, g = 0, b = 0, a = 0.25 }

QSF_Theme.COL_TITLE = { r = 0.90, g = 0.91, b = 0.90 }
QSF_Theme.COL_TEXT = { r = 0.68, g = 0.68, b = 0.68 }
QSF_Theme.COL_DIM = { r = 0.50, g = 0.50, b = 0.50 }
QSF_Theme.COL_COUNT = { r = 0.80, g = 0.74, b = 0.50 }

QSF_Theme.COL_ACTIVE = { r = 0.98, g = 0.82, b = 0.45 }
QSF_Theme.COL_DONE = { r = 0.48, g = 0.76, b = 0.48 }
QSF_Theme.COL_LOCKED = { r = 0.45, g = 0.45, b = 0.45 }

local TEXTURES = nil

function QSF_Theme.textures()
    if TEXTURES == nil then
        TEXTURES = {
            left = getTexture("media/ui/NeatUI/Button/Button_FULL_L.png"),
            middle = getTexture("media/ui/NeatUI/Button/Button_FULL_M.png"),
            right = getTexture("media/ui/NeatUI/Button/Button_FULL_R.png"),
            iconTrue = getTexture("media/ui/NeatUI/ICON/Icon_True.png"),
            iconFalse = getTexture("media/ui/NeatUI/ICON/Icon_False.png"),
        }
    end
    return TEXTURES
end

-- every child goes on the same way. anchors are applied by instantiate(), so they have to
-- be on the child before it runs.
function QSF_Theme.attach(parent, child, anchors)
    for key, value in pairs(anchors or {}) do child[key] = value end
    child:initialise()
    child:instantiate()
    parent:addChild(child)
    return child
end

-- getItemDisplayName is empty for a type the game does not know, and the full type is more
-- use to whoever wrote the quest than a blank line would be.
function QSF_Theme.itemName(fullType)
    local display = getItemDisplayName(fullType)
    if display and display ~= "" then return display end
    return fullType
end

-- a quest file names a perk the way the engine does, Woodwork, and the character sheet calls
-- that one Carpentry. a name the game has no perk for is shown as it was written, the same
-- as an item is.
function QSF_Theme.perkName(name)
    local perk = QSF_Rules.perk(name)
    if not perk then return name end

    local display = PerkFactory.getPerkName(perk)
    if display and display ~= "" then return display end
    return name
end

-- NeatUI fails silently when it has not loaded, so nothing calls truncateText directly.
function QSF_Theme.truncate(text, maxWidth, font)
    if NeatTool and type(NeatTool.truncateText) == "function" then
        return NeatTool.truncateText(text, maxWidth, font or UIFont.Small)
    end
    return text
end
