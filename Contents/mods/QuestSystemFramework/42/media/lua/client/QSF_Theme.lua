----------
--ESTRAL--
----------

require "QSF_Rules"

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

-- the grey a disabled button's label is, for text that is not on a button.
QSF_Theme.COL_DISABLED = { r = 0.42, g = 0.42, b = 0.42 }

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

-- a window of the mod's own, put on the screen and in front of what is there.
function QSF_Theme.open(window)
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    window:bringToTop()
    return window
end

-- what a small form that floats over the game looks like: the picker, and the npc form.
function QSF_Theme.floating(panel)
    panel.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.95 }
    panel.borderColor = QSF_Theme.COL_FRAME
    panel.moveWithMouse = true
end

-- Confirm and Cancel along the bottom of one of those, against the right edge with Cancel
-- outermost. returns the two of them in that order.
function QSF_Theme.okCancel(panel, y, height, pad, onOk, onCancel)
    local cancel = QSF_Button:new(0, y, 10, height, getText("IGUI_QSF_Cancel"), panel, onCancel)
    cancel:sizeToTitle(28)
    cancel:setX(panel.width - pad - cancel:getWidth())
    QSF_Theme.attach(panel, cancel)

    local confirm = QSF_Button:new(0, y, 10, height, getText("IGUI_QSF_Confirm"), panel, onOk)
    confirm:sizeToTitle(28)
    confirm:setX(cancel:getX() - 6 - confirm:getWidth())
    QSF_Theme.attach(panel, confirm)

    return confirm, cancel
end

-- NeatUI's list, which builds only as many widgets as fit and hands them round as it
-- scrolls, so a widget is whichever entry it was last given. create makes one and fill
-- gives it an entry.
function QSF_Theme.scrollList(parent, x, y, width, height, rowHeight, gap, create, fill)
    local list = NIVirtualScrollView:new(x, y, width, height)
    list:initialise()
    list:instantiate()
    -- setOnCreateItem after instantiate: createChildren already ran initializePool once
    -- with no callback set and quietly did nothing.
    list:setOnCreateItem(function()
        local widget = create(list)
        -- the pool calls initialise for us but not instantiate.
        widget:instantiate()
        return widget
    end)
    list:setOnUpdateItem(fill)
    list:setConfig(rowHeight, gap)
    parent:addChild(list)

    return list
end

-- text in one of the colours above. small, unless it says otherwise.
function QSF_Theme.text(panel, text, x, y, colour, font)
    panel:drawText(text, x, y, colour.r, colour.g, colour.b, 1, font or UIFont.Small)
end

-- rich text with no chrome and no margins, as tall as what is put in it. it is what gives
-- a description or a line of dialogue <LINE> and <RGB:> for free.
function QSF_Theme.richText(parent, x, y, width, height)
    local panel = ISRichTextPanel:new(x, y, width, height)

    panel:initialise()
    panel.background = false
    panel.autosetheight = true
    panel.marginLeft = 0
    panel.marginRight = 0
    panel.marginTop = 0
    parent:addChild(panel)

    return panel
end

-- the top-left corner that puts something this size in the middle of the screen.
function QSF_Theme.centre(width, height)
    return (getCore():getScreenWidth() - width) / 2, (getCore():getScreenHeight() - height) / 2
end

-- a yes or no prompt, mid-screen. the callback gets the button and then param. nothing
-- under a modal stops being clickable, so the caller holds what this returns if a second
-- press must not stack a second prompt.
function QSF_Theme.confirm(text, target, callback, playerNum, param)
    local x, y = QSF_Theme.centre(350, 150)
    local modal = ISModalDialog:new(x, y, 350, 150, text, true, target, callback, playerNum, param)

    modal:initialise()
    modal:addToUIManager()
    modal:bringToTop()

    return modal
end

-- "Nails x20", or only the name when there is the one of it.
function QSF_Theme.itemLabel(entry)
    local name = QSF_Theme.itemName(entry.item)
    if entry.count > 1 then return name .. " x" .. entry.count end
    return name
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
