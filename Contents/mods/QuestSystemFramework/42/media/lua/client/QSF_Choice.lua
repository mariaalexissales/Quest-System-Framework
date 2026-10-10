----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "QSF_Button"
require "QSF_Theme"
require "QSF_Rules"
require "QSF_ClientState"

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

function QSF_Choice:new(x, y, width, height, def, key, target, after)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.def = def
    o.questKey = key
    o.target = target
    o.after = after
    o.pick = nil
    o.options = def.rewards.choice.options
    o.header = def.rewards.choice.label or getText("IGUI_QSF_ChooseReward")

    QSF_Theme.floating(o)

    o.headerHeight = getTextManager():getFontHeight(UIFont.Medium)

    return o
end

function QSF_Choice:createChildren()
    ISPanel.createChildren(self)

    local y = PAD + self.headerHeight + GAP

    self.picks = {}
    for index, entry in ipairs(self.options) do
        local button = QSF_Button:new(PAD, y, self.width - PAD * 2, OPTION_HEIGHT,
            QSF_Theme.truncate(QSF_Theme.itemLabel(entry), self.width - PAD * 2 - 24, UIFont.Small),
            self, QSF_Choice.onPick)
        -- the ordinal is what travels to the server, so it is carried on the widget the
        -- same way the tab buttons carry theirs.
        button.index = index
        self.picks[index] = QSF_Theme.attach(self, button)

        y = y + OPTION_HEIGHT + OPTION_GAP
    end

    self.confirm, self.cancel = QSF_Theme.okCancel(self, self.height - PAD - BUTTON_HEIGHT, BUTTON_HEIGHT, PAD,
        QSF_Choice.onOk, QSF_Choice.onCancel)
    -- nothing is picked yet, and a confirm with no pick is a refusal waiting to happen.
    self.confirm:setEnable(false)
end

function QSF_Choice:onPick(button)
    self.pick = button.index

    for index, widget in ipairs(self.picks) do
        widget.selected = index == self.pick
    end

    -- the same rule the server pays out by, so Confirm cannot light up for a pick it refuses.
    if self.confirm then self.confirm:setEnable(QSF_Rules.pickedReward(self.def, self.pick) ~= nil) end
end

-- the quest it was opened for, whatever has been selected since: a selection that moves
-- while the picker is up must not pay out a different quest.
function QSF_Choice:onOk()
    if not self.pick then return end

    local target, after, key, pick = self.target, self.after, self.questKey, self.pick
    self:close()

    QSF_ClientState.claim(key, pick)
    if after then after(target) end
end

-- the quest is still active and still complete, so the button that opened this goes back
-- to reading Turn In and nothing was spent.
function QSF_Choice:onCancel()
    self:close()
end

function QSF_Choice:close()
    -- whoever opened it is holding it as a guard, and is let go of here whichever way
    -- it closes.
    if self.target and self.target.choiceModal == self then self.target.choiceModal = nil end

    self:setVisible(false)
    self:removeFromUIManager()
end

function QSF_Choice:render()
    ISPanel.render(self)

    QSF_Theme.text(self, QSF_Theme.truncate(self.header, self.width - PAD * 2, UIFont.Medium), PAD, PAD,
        QSF_Theme.COL_TITLE, UIFont.Medium)
end

-- centred on the screen the way the teleport prompt is. the target holds it as choiceModal
-- until it closes: nothing under a picker stops being clickable, and a second press would
-- otherwise stack a second one on the first.
function QSF_Choice.show(def, key, target, after)
    if target.choiceModal then return target.choiceModal end

    local choice = def and def.rewards and def.rewards.choice
    if not choice or #choice.options == 0 then return nil end

    local headerHeight = getTextManager():getFontHeight(UIFont.Medium)
    local height = QSF_height(#choice.options, headerHeight)

    local x, y = QSF_Theme.centre(WIDTH, height)

    target.choiceModal = QSF_Theme.open(QSF_Choice:new(x, y, WIDTH, height, def, key, target, after))
    return target.choiceModal
end

-- handing a quest in, from whichever window. it goes straight to the server unless there
-- is a reward to pick first, and then the picker sends it once one has been. after is the
-- window's own, called with it when that happens. true when it has already gone.
function QSF_Choice.turnIn(def, key, target, after)
    if def.rewards and def.rewards.choice then
        QSF_Choice.show(def, key, target, after)
        return false
    end

    QSF_ClientState.claim(key)
    return true
end

-- for a window that is closing with its picker still up. the picker is a top-level window,
-- so it would otherwise outlive whatever it belongs to.
function QSF_Choice.dismiss(target)
    if target.choiceModal then target.choiceModal:close() end
end
