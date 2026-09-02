----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "QSF_Theme"
require "QSF_Location"

QSF_Row = ISPanel:derive("QSF_Row")
QSF_Row.HEIGHT = 46

local PAD = 8
local ACCENT = 2
local LINE_ONE = 7
local LINE_TWO = 25
local BAR_HEIGHT = 2

function QSF_Row:new(x, y, width, height, panel)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.panel = panel
    o.row = nil
    o.backgroundColor = { r = 1, g = 1, b = 1, a = 0.03 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false

    return o
end

function QSF_Row:setRow(row)
    self.row = row
end

function QSF_Row:isSelected()
    return self.row and self.panel and self.panel.selected == self.row.key
end

function QSF_Row:onMouseDown(x, y)
    if not self.row or not self.panel then return end
    -- a locked quest still shows its detail pane, because that is where the player finds
    -- out what is blocking it. it just cannot be accepted.
    self.panel:select(self.row.key)
end

function QSF_Row:prerender()
    if self:isSelected() then
        self.backgroundColor.a = 0.10
    elseif self:isMouseOver() then
        self.backgroundColor.a = 0.08
    else
        self.backgroundColor.a = 0.03
    end

    ISPanel.prerender(self)
end

function QSF_Row:render()
    ISPanel.render(self)

    local row = self.row
    if not row then return end

    local accent = QSF_Theme.COL_ACTIVE
    if row.status == "done" then accent = QSF_Theme.COL_DONE
    elseif row.locked then accent = QSF_Theme.COL_LOCKED end

    self:drawRect(0, 0, ACCENT, self.height, 0.85, accent.r, accent.g, accent.b)

    local titleColour = row.locked and QSF_Theme.STATES.disabled.text or nil
    local tr = titleColour and titleColour[1] or QSF_Theme.COL_TITLE.r
    local tg = titleColour and titleColour[2] or QSF_Theme.COL_TITLE.g
    local tb = titleColour and titleColour[3] or QSF_Theme.COL_TITLE.b

    local x = PAD + ACCENT
    local counter = row.counter or ""
    local counterWidth = counter ~= "" and getTextManager():MeasureStringX(UIFont.Small, counter) or 0
    local limit = self.width - PAD - counterWidth - (counterWidth > 0 and PAD or 0)

    local title = QSF_Theme.truncate(row.title or "?", limit - x, UIFont.Small)
    self:drawText(title, x, LINE_ONE, tr, tg, tb, 1, UIFont.Small)

    if counter ~= "" then
        local col = row.locked and QSF_Theme.COL_DIM or QSF_Theme.COL_COUNT
        self:drawText(counter, self.width - PAD - counterWidth, LINE_ONE, col.r, col.g, col.b, 1, UIFont.Small)
    end

    local subtitle = row.subtitle
    if subtitle and subtitle ~= "" then
        local sub = QSF_Theme.truncate(subtitle, self.width - x - PAD, UIFont.Small)
        local col = row.locked and QSF_Theme.STATES.disabled.text or nil
        local sr = col and col[1] or QSF_Theme.COL_DIM.r
        local sg = col and col[2] or QSF_Theme.COL_DIM.g
        local sb = col and col[3] or QSF_Theme.COL_DIM.b
        self:drawText(sub, x, LINE_TWO, sr, sg, sb, 1, UIFont.Small)
    end

    -- only active quests get a bar; on anything else it would either be empty or full
    -- and would say nothing.
    if row.status == "active" and row.progress and row.progress > 0 then
        local width = math.floor((self.width - ACCENT) * math.min(1, row.progress))
        self:drawRect(ACCENT, self.height - BAR_HEIGHT, width, BAR_HEIGHT,
            0.75, QSF_Theme.COL_ACTIVE.r, QSF_Theme.COL_ACTIVE.g, QSF_Theme.COL_ACTIVE.b)
    end
end
