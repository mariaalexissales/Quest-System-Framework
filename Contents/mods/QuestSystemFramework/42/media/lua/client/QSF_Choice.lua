----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "QSF_Button"
require "QSF_Theme"
require "QSF_Rules"

QSF_Choice = ISPanel:derive("QSF_Choice")

local PAD = 12
local GAP = 8
local OPTION_HEIGHT = 24
local OPTION_GAP = 4
local BUTTON_HEIGHT = 24
local WIDTH = 340

-- the picker is sized to its pool rather than scrolled: the schema warns an author past
-- eight options, and eight rows still fit a screen comfortably.
local function QSF_height(count, headerHeight)
    local rows = count * OPTION_HEIGHT + math.max(0, count - 1) * OPTION_GAP
    return PAD + headerHeight + GAP + rows + GAP + BUTTON_HEIGHT + PAD
end

function QSF_Choice:new(x, y, width, height, def, key, target, onConfirm)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.def = def
    o.questKey = key
    o.target = target
    o.onConfirm = onConfirm
    o.pick = nil
    o.options = def.rewards.choice.options
    o.header = def.rewards.choice.label or getText("IGUI_QSF_ChooseReward")

    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.95 }
    o.borderColor = QSF_Theme.COL_FRAME
    o.moveWithMouse = true

    o.headerHeight = getTextManager():getFontHeight(UIFont.Medium)

    return o
end

function QSF_Choice:createChildren()
    ISPanel.createChildren(self)

    local y = PAD + self.headerHeight + GAP

    self.picks = {}
    for index, entry in ipairs(self.options) do
        local title = QSF_Theme.itemName(entry.item)
        if entry.count > 1 then title = title .. " x" .. entry.count end

        local button = QSF_Button:new(PAD, y, self.width - PAD * 2, OPTION_HEIGHT,
            QSF_Theme.truncate(title, self.width - PAD * 2 - 24, UIFont.Small),
            self, QSF_Choice.onPick)
        -- the ordinal is what travels to the server, so it is carried on the widget the
        -- same way the tab buttons carry theirs.
        button.index = index
        self.picks[index] = QSF_Theme.attach(self, button)

        y = y + OPTION_HEIGHT + OPTION_GAP
    end

    y = self.height - PAD - BUTTON_HEIGHT

    self.cancel = QSF_Button:new(0, y, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Cancel"), self, QSF_Choice.onCancel)
    self.cancel:sizeToTitle(28)
    self.cancel:setX(self.width - PAD - self.cancel:getWidth())
    QSF_Theme.attach(self, self.cancel)

    self.confirm = QSF_Button:new(0, y, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Confirm"), self, QSF_Choice.onOk)
    self.confirm:sizeToTitle(28)
    self.confirm:setX(self.cancel:getX() - 6 - self.confirm:getWidth())
    -- nothing is picked yet, and a confirm with no pick is a refusal waiting to happen.
    self.confirm:setEnable(false)
    QSF_Theme.attach(self, self.confirm)
end

function QSF_Choice:onPick(button)
    self.pick = button.index

    for index, widget in ipairs(self.picks) do
        widget.selected = index == self.pick
    end

    -- the same rule the server pays out by, so Confirm cannot light up for a pick it refuses.
    if self.confirm then self.confirm:setEnable(QSF_Rules.pickedReward(self.def, self.pick) ~= nil) end
end

function QSF_Choice:onOk()
    if not self.pick then return end

    local target, callback, key, pick = self.target, self.onConfirm, self.questKey, self.pick
    self:close()

    if callback then callback(target, key, pick) end
end

function QSF_Choice:onCancel()
    self:close()

    -- the quest is still active and still complete, so the footer button goes back to
    -- reading Turn In and nothing was spent.
    if self.target and self.target.onCancelChoice then
        self.target:onCancelChoice()
    end
end

function QSF_Choice:close()
    self:setVisible(false)
    self:removeFromUIManager()
end

function QSF_Choice:render()
    ISPanel.render(self)

    QSF_Theme.text(self, QSF_Theme.truncate(self.header, self.width - PAD * 2, UIFont.Medium), PAD, PAD,
        QSF_Theme.COL_TITLE, UIFont.Medium)
end

-- centred on the screen the way the teleport prompt is, and handed back so the caller can
-- hold it as its own reentrancy guard.
function QSF_Choice.show(def, key, target, onConfirm)
    local choice = def and def.rewards and def.rewards.choice
    if not choice or #choice.options == 0 then return nil end

    local headerHeight = getTextManager():getFontHeight(UIFont.Medium)
    local height = QSF_height(#choice.options, headerHeight)

    local x, y = QSF_Theme.centre(WIDTH, height)

    local picker = QSF_Choice:new(x, y, WIDTH, height, def, key, target, onConfirm)
    picker:initialise()
    picker:instantiate()
    picker:addToUIManager()
    picker:bringToTop()

    return picker
end
