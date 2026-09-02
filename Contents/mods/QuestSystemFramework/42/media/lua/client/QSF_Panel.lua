----------
--ESTRAL--
----------

require "ISUI/ISCollapsableWindow"
require "QSF_Button"
require "QSF_Row"
require "QSF_Detail"
require "QSF_Theme"
require "QSF_ClientState"
require "QSF_Rules"
require "QSF_Location"

QSF = QSF or {}
QSF.players = QSF.players or {}

QSF_Panel = ISCollapsableWindow:derive("QSF_Panel")

local PAD = 8
local GAP = 6
local TAB_HEIGHT = 22
local FOOTER_HEIGHT = 30
local REFRESH_TICKS = 30

function QSF.getWindow(playerNum)
    local data = QSF.players[playerNum]
    return data and data.instance or nil
end

function QSF.isWindowOpen(playerNum)
    return QSF.getWindow(playerNum) ~= nil
end

function QSF_Panel:new(x, y, width, height, player)
    local o = ISCollapsableWindow:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.playerNum = player:getPlayerNum()
    o.title = getText("IGUI_QSF_Title")
    o.tab = "active"
    o.selected = nil
    o.rows = {}
    o.ticks = 0
    o.revision = -1
    o.resizable = true
    o.minimumWidth = 720
    o.minimumHeight = 440

    return o
end

-- one place for the vertical bands so createChildren and onResize cannot drift. a
-- resizable ISCollapsableWindow paints a status bar over its own bottom edge and lays
-- a resize widget across it that swallows clicks, so the footer sits above that.
function QSF_Panel:bands()
    local tabY = self:titleBarHeight() + PAD
    local listY = tabY + TAB_HEIGHT + GAP
    local footerY = self.height - self:resizeWidgetHeight() - FOOTER_HEIGHT
    local listW = math.max(260, math.min(420, math.floor(self.width * 0.40)))
    return tabY, listY, footerY, listW
end

-- the footer button swaps between Accept, Turn In and Abandon, so it is sized for the
-- widest of them and the strip never reflows mid-use.
local function QSF_labelWidth(button, ...)
    local widest = 0
    for _, key in ipairs({ ... }) do
        widest = math.max(widest, getTextManager():MeasureStringX(button.font, getText(key)))
    end
    return 24 + widest
end

-- anchors are applied by instantiate(), so they have to be assigned before it runs.
function QSF_Panel:attach(button, anchors)
    for key, value in pairs(anchors or {}) do button[key] = value end
    button:initialise()
    button:instantiate()
    self:addChild(button)
    return button
end

function QSF_Panel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local tabY, listY, footerY, listW = self:bands()

    self.tabActive = QSF_Button:new(PAD, tabY, 10, TAB_HEIGHT, getText("IGUI_QSF_TabActive"), self, QSF_Panel.onTab)
    self.tabActive:sizeToTitle(28)
    self.tabActive.tab = "active"
    self:attach(self.tabActive)

    self.tabAvailable = QSF_Button:new(self.tabActive:getRight() + 4, tabY, 10, TAB_HEIGHT,
        getText("IGUI_QSF_TabAvailable"), self, QSF_Panel.onTab)
    self.tabAvailable:sizeToTitle(28)
    self.tabAvailable.tab = "available"
    self:attach(self.tabAvailable)

    self.tabDone = QSF_Button:new(self.tabAvailable:getRight() + 4, tabY, 10, TAB_HEIGHT,
        getText("IGUI_QSF_TabDone"), self, QSF_Panel.onTab)
    self.tabDone:sizeToTitle(28)
    self.tabDone.tab = "done"
    self:attach(self.tabDone)

    local listHeight = footerY - listY - GAP - 2

    self.list = NIVirtualScrollView:new(PAD + 1, listY + 1, listW - 2, listHeight)
    self.list:initialise()
    self.list:instantiate()
    -- setOnCreateItem has to come after instantiate: createChildren already ran
    -- initializePool once with no callback set, and it quietly did nothing.
    self.list:setOnCreateItem(function()
        local row = QSF_Row:new(0, 0, self.list:getWidth(), QSF_Row.HEIGHT, self)
        -- the pool calls initialise for us but not instantiate.
        row:instantiate()
        return row
    end)
    self.list:setOnUpdateItem(function(widget, data)
        widget:setWidth(self.list:getWidth())
        widget:setRow(data)
    end)
    self.list:setConfig(QSF_Row.HEIGHT, 4)
    self.listHeight = listHeight
    self:addChild(self.list)

    self.detail = QSF_Detail:new(PAD + listW + GAP, listY, self.width - listW - PAD * 2 - GAP, listHeight)
    self.detail:initialise()
    self.detail:instantiate()
    self:addChild(self.detail)

    self.action = QSF_Button:new(PAD, footerY + 2, 10, FOOTER_HEIGHT - 6, getText("IGUI_QSF_Accept"), self, QSF_Panel.onAction)
    self.action:setWidth(QSF_labelWidth(self.action, "IGUI_QSF_Accept", "IGUI_QSF_TurnIn", "IGUI_QSF_Abandon"))
    self:attach(self.action)

    self.reload = QSF_Button:new(self.width - PAD - 90, footerY + 2, 90, FOOTER_HEIGHT - 6,
        getText("IGUI_QSF_Reload"), self, QSF_Panel.onReload)
    self:attach(self.reload, { anchorLeft = false, anchorRight = true })

    self:refresh()
end

function QSF_Panel:onTab(button)
    self.tab = button.tab
    self.selected = nil
    self:refresh()
end

function QSF_Panel:select(key)
    self.selected = key
    if self.detail then self.detail:setKey(key) end
end

function QSF_Panel:onAction()
    if not self.selected then return end

    local def = QSF_ClientState.defs[self.selected]
    if not def then return end

    local rec = QSF_ClientState.record(self.selected)

    if rec and rec.status == "active" then
        if QSF_Rules.isComplete(def, rec, QSF_ClientState.counts()) then
            QSF_ClientState.claim(self.selected)
        else
            QSF_ClientState.abandon(self.selected)
        end
        return
    end

    QSF_ClientState.accept(self.selected)
end

function QSF_Panel:onReload()
    QSF_ClientState.reload()
end

-- ---------------------------------------------------------------------------
-- building the list
-- ---------------------------------------------------------------------------

function QSF_Panel:buildRows()
    local rows = {}
    local counts = QSF_ClientState.counts()

    for _, def in ipairs(QSF_ClientState.ordered) do
        local rec = QSF_ClientState.record(def.key)
        local status = rec and rec.status or nil
        local ok, reason, detail = QSF_Rules.canAccept(def, rec, self.player, QSF_ClientState.state)

        local wanted = false
        if self.tab == "active" then
            wanted = status == "active"
        elseif self.tab == "done" then
            wanted = status == "done"
        else
            -- available holds everything not started, plus a repeatable that has come
            -- off cooldown and can be taken again.
            wanted = status ~= "active" and (status ~= "done" or ok)
            -- a hidden prereq means the quest should not even hint at itself yet.
            if wanted and not ok and def.prereqs and def.prereqs.hidden then wanted = false end
        end

        if wanted then
            local locked = self.tab == "available" and not ok
            local row = {
                key = def.key,
                title = def.title,
                status = status,
                locked = locked,
                subtitle = QSF_Location.describe(def.location),
            }

            if status == "active" then
                local done = 0
                for i, obj in ipairs(def.objectives) do
                    local _, _, satisfied = QSF_Rules.objectiveProgress(obj, i, rec, counts)
                    if satisfied then done = done + 1 end
                end

                if #def.objectives == 1 then
                    local have, need = QSF_Rules.objectiveProgress(def.objectives[1], 1, rec, counts)
                    row.counter = have .. "/" .. need
                else
                    row.counter = done .. "/" .. #def.objectives
                end

                row.progress = QSF_Rules.overallProgress(def, rec, counts)
            elseif locked then
                row.subtitle = QSF_Detail.reasonText(reason, detail) or row.subtitle
            elseif status == "done" and rec and (rec.turnins or 0) > 1 then
                row.counter = "x" .. rec.turnins
            end

            rows[#rows + 1] = row
        end
    end

    return rows
end

function QSF_Panel:refresh()
    self.rows = self:buildRows()

    -- the scroll view only reassigns data when the visible range moves, so a refresh
    -- that leaves the row count alone has to be forced through.
    if self.list then self.list:setDataSource(self.rows, true) end

    -- a selection that fell out of the current tab would leave the pane showing
    -- something the list no longer offers.
    if self.selected then
        local stillThere = false
        for _, row in ipairs(self.rows) do
            if row.key == self.selected then
                stillThere = true
                break
            end
        end
        if not stillThere then self.selected = nil end
    end

    if not self.selected and self.rows[1] then self.selected = self.rows[1].key end
    if self.detail then self.detail:setKey(self.selected) end

    self:updateAction()
end

function QSF_Panel:updateAction()
    if not self.action then return end

    local def = self.selected and QSF_ClientState.defs[self.selected] or nil

    if not def then
        self.action:setTitle(getText("IGUI_QSF_Accept"))
        self.action:setEnable(false)
        return
    end

    local rec = QSF_ClientState.record(self.selected)

    if rec and rec.status == "active" then
        if QSF_Rules.isComplete(def, rec, QSF_ClientState.counts()) then
            self.action:setTitle(getText("IGUI_QSF_TurnIn"))
        else
            self.action:setTitle(getText("IGUI_QSF_Abandon"))
        end
        self.action:setEnable(true)
        return
    end

    -- the same predicate the row used to grey itself, so the button and the list can
    -- never disagree about whether this is allowed.
    local ok = QSF_Rules.canAccept(def, rec, self.player, QSF_ClientState.state)
    self.action:setTitle(getText("IGUI_QSF_Accept"))
    self.action:setEnable(ok == true)
end

function QSF_Panel:prerender()
    ISCollapsableWindow.prerender(self)

    local tabY, listY, footerY, listW = self:bands()

    self:drawRect(PAD, listY, listW, footerY - listY - GAP,
        QSF_Theme.COL_WELL.a, QSF_Theme.COL_WELL.r, QSF_Theme.COL_WELL.g, QSF_Theme.COL_WELL.b)
    self:drawRectBorder(PAD, listY, listW, footerY - listY - GAP,
        QSF_Theme.COL_FRAME.a, QSF_Theme.COL_FRAME.r, QSF_Theme.COL_FRAME.g, QSF_Theme.COL_FRAME.b)

    -- the divider between the two columns.
    self:drawRect(PAD + listW + GAP / 2, listY, 1, footerY - listY - GAP,
        QSF_Theme.COL_FRAME.a, QSF_Theme.COL_FRAME.r, QSF_Theme.COL_FRAME.g, QSF_Theme.COL_FRAME.b)

    self.tabActive.selected = self.tab == "active"
    self.tabAvailable.selected = self.tab == "available"
    self.tabDone.selected = self.tab == "done"

    -- access level is a java call and prerender runs every frame, so it is asked
    -- once and kept. it cannot change mid-session without a reconnect anyway.
    if self.reload then
        if self.isAdmin == nil then self.isAdmin = QSF.isAdmin(self.player) end
        self.reload:setVisible(self.isAdmin)
    end
end

function QSF_Panel:render()
    ISCollapsableWindow.render(self)

    if #self.rows == 0 then
        local _, listY, _, listW = self:bands()
        local text = QSF_ClientState.ready and getText("IGUI_QSF_Empty_" .. self.tab) or getText("IGUI_QSF_Connecting")
        self:drawText(text, PAD + 10, listY + 10,
            QSF_Theme.COL_DIM.r, QSF_Theme.COL_DIM.g, QSF_Theme.COL_DIM.b, 1, UIFont.Small)
    end
end

function QSF_Panel:update()
    ISCollapsableWindow.update(self)

    -- the cache bumps a revision whenever the server says something, and the poll bumps
    -- it when a count moves. the tick floor is only a backstop for anything that changes
    -- without either.
    self.ticks = self.ticks + 1

    if self.revision ~= QSF_ClientState.revision then
        self.revision = QSF_ClientState.revision
        self.ticks = 0
        self:refresh()
    elseif self.ticks >= REFRESH_TICKS then
        self.ticks = 0
        self:updateAction()
    end
end

function QSF_Panel:onResize()
    ISCollapsableWindow.onResize(self)
    if not self.list then return end

    local _, listY, footerY, listW = self:bands()
    local listHeight = footerY - listY - GAP - 2

    self.list:setWidth(listW - 2)
    self.list:setHeight(listHeight)

    -- setConfig rebuilds the whole widget pool and onResize fires every frame of a
    -- drag, so only reconfigure when the height actually moved.
    if self.listHeight ~= listHeight then
        self.listHeight = listHeight
        self.list:setConfig(QSF_Row.HEIGHT, 4)
    end

    self.list:setDataSource(self.rows, true)

    if self.detail then
        self.detail:setX(PAD + listW + GAP)
        self.detail:setY(listY)
        self.detail:setWidth(self.width - listW - PAD * 2 - GAP)
        self.detail:setHeight(listHeight)
        self.detail:onResize()
    end

    if self.action then self.action:setY(footerY + 2) end
    if self.reload then self.reload:setY(footerY + 2) end
end

function QSF_Panel:close()
    local data = QSF.players[self.playerNum]
    if data and data.instance == self then
        data.x = self:getX()
        data.y = self:getY()
        data.instance = nil
    end

    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

function QSF.openPanel(player)
    if not player then return end

    local playerNum = player:getPlayerNum()
    if playerNum ~= 0 then return end

    local data = QSF.players[playerNum]
    if not data then
        data = {}
        QSF.players[playerNum] = data
    end

    if data.instance then
        data.instance:setVisible(true)
        data.instance:bringToTop()
        return
    end

    local width, height = 880, 600
    local x = data.x or (getCore():getScreenWidth() - width) / 2
    local y = data.y or (getCore():getScreenHeight() - height) / 2

    local window = QSF_Panel:new(x, y, width, height, player)
    window:initialise()
    window:instantiate()
    window:addToUIManager()

    data.instance = window
end

function QSF.togglePanel(player)
    local playerNum = player and player:getPlayerNum() or 0

    if QSF.isWindowOpen(playerNum) then
        QSF.getWindow(playerNum):close()
    else
        QSF.openPanel(player)
    end
end

Events.OnPlayerDeath.Add(function(player)
    if not player then return end

    local window = QSF.getWindow(player:getPlayerNum())
    if window then window:close() end
end)
