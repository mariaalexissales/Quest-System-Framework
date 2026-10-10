----------
--ESTRAL--
----------

require "ISUI/ISCollapsableWindow"
require "ISUI/ISModalDialog"
require "QSF_Button"
require "QSF_Row"
require "QSF_Detail"
require "QSF_Choice"
require "QSF_Theme"
require "QSF_ClientState"
require "QSF_Rules"
require "QSF_Location"

QSF.players = QSF.players or {}

QSF_Panel = ISCollapsableWindow:derive("QSF_Panel")

local PAD = 8
local GAP = 6
local TAB_HEIGHT = 22
local FOOTER_HEIGHT = 30
local REFRESH_TICKS = 30

-- left to right. the name is also the end of the line a tab shows when it has nothing in it.
local TABS = {
    { name = "active", title = "IGUI_QSF_TabActive" },
    { name = "available", title = "IGUI_QSF_TabAvailable" },
    { name = "done", title = "IGUI_QSF_TabDone" },
    { name = "global", title = "IGUI_QSF_TabGlobal" },
}

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

-- one along the footer. the titles are translation keys: the first is what it opens
-- reading, and one that swaps between several is as wide as the widest of them, so the
-- strip never reflows mid-use.
function QSF_Panel:footerButton(x, y, onClick, title, ...)
    local button = QSF_Button:new(x, y + 2, 90, FOOTER_HEIGHT - 6, getText(title), self, onClick)
    if select("#", ...) > 0 then button:sizeToWidest(24, title, ...) end
    return button
end

function QSF_Panel:createChildren()
    ISCollapsableWindow.createChildren(self)

    local tabY, listY, footerY, listW = self:bands()

    self.tabs = {}
    local x = PAD
    for _, tab in ipairs(TABS) do
        local button = QSF_Button:new(x, tabY, 10, TAB_HEIGHT, getText(tab.title), self, QSF_Panel.onTab)
        button:sizeToTitle(28)
        button.tab = tab.name
        self.tabs[tab.name] = QSF_Theme.attach(self, button)

        x = button:getRight() + 4
    end

    local listHeight = footerY - listY - GAP - 2

    self.list = QSF_Theme.scrollList(self, PAD + 1, listY + 1, listW - 2, listHeight, QSF_Row.HEIGHT, 4,
        function(list)
            return QSF_Row:new(0, 0, list:getWidth(), QSF_Row.HEIGHT, self)
        end,
        function(widget, data)
            widget:setWidth(self.list:getWidth())
            widget:setRow(data)
        end)
    self.listHeight = listHeight

    self.detail = QSF_Theme.attach(self,
        QSF_Detail:new(PAD + listW + GAP, listY, self.width - listW - PAD * 2 - GAP, listHeight))

    self.action = QSF_Theme.attach(self, self:footerButton(PAD, footerY, QSF_Panel.onAction,
        "IGUI_QSF_Accept", "IGUI_QSF_TurnIn", "IGUI_QSF_Abandon", "IGUI_QSF_Contribute"))

    -- beside the action button, which keeps a fixed x and a fixed width, so its right edge
    -- is a stable anchor.
    self.teleport = QSF_Theme.attach(self, self:footerButton(self.action:getRight() + 4, footerY,
        QSF_Panel.onTeleport, "IGUI_QSF_Teleport", "IGUI_QSF_TeleportCooldown"))

    local right = { anchorLeft = false, anchorRight = true }

    self.reload = QSF_Theme.attach(self, self:footerButton(self.width - PAD - 90, footerY,
        QSF_Panel.onReload, "IGUI_QSF_Reload"), right)

    -- beside Reload and anchored the same way. one button, since a global quest is only
    -- ever waiting to be started or running to be ended.
    self.globalRun = QSF_Theme.attach(self, self:footerButton(self.width - PAD - 90 - 4 - 90, footerY,
        QSF_Panel.onRun, "IGUI_QSF_GlobalStart"), right)

    self:refresh()
end

function QSF_Panel:onTab(button)
    self.tab = button.tab
    self.selected = nil
    self:refresh()
end

function QSF_Panel:isGlobal()
    return self.tab == "global"
end

function QSF_Panel:select(key)
    self.selected = key
    if self.detail then self.detail:setKey(key, self:isGlobal()) end
end

-- the selected global quest and the server's run of it, or nothing on any other tab.
function QSF_Panel:globalSelection()
    if not self:isGlobal() or not self.selected then return nil end

    local def = QSF_ClientState.globalDefs[self.selected]
    if not def then return nil end

    return def, QSF_ClientState.global[self.selected]
end

-- a yes or no before something that cannot be walked back. accept, abandon and turn in all
-- fire on the click, and these do not. slot is where the prompt is held while it is up:
-- nothing under a modal stops being clickable, so a second press would stack a second
-- prompt on the first, and vanilla guards its sleep dialog the same way. the key travels
-- with the prompt, so a selection that moves while it is open cannot send the answer to a
-- different quest.
function QSF_Panel:ask(slot, text, send)
    if self[slot] or not self.selected then return end

    self[slot] = QSF_Theme.confirm(text, self, function(panel, button, key)
        panel[slot] = nil
        if button.internal == "YES" and key then send(key) end
    end, self.playerNum, self.selected)
end

-- handing over cannot be walked back any more than a teleport can, so it says how many.
function QSF_Panel:onContribute()
    local def, run = self:globalSelection()
    if not def then return end

    local total = QSF_Rules.givable(def, run, QSF_ClientState.counts())
    if total == 0 then return end

    self:ask("giveModal", getText("IGUI_QSF_ContributeConfirm", tostring(total)), QSF_ClientState.globalGive)
end

-- starting is one click. ending pays everybody the consolation, so that one asks.
function QSF_Panel:onRun()
    local def, run = self:globalSelection()
    if not def then return end

    if not run or run.status ~= "active" then
        QSF_ClientState.globalStart(self.selected)
        return
    end

    self:ask("endModal", getText("IGUI_QSF_GlobalEndConfirm"), QSF_ClientState.globalEnd)
end

function QSF_Panel:onAction()
    if not self.selected then return end

    if self:isGlobal() then
        self:onContribute()
        return
    end

    local def = QSF_ClientState.defs[self.selected]
    if not def then return end

    local state = QSF_ClientState.stateOf(def, self.player)

    if state == "progress" then
        QSF_ClientState.abandon(self.selected)
        return
    end

    -- the button is greyed for these, but a click can beat the refresh that greys it.
    if def.giver then return end

    if state == "turnin" then
        QSF_Choice.turnIn(def, self.selected, self)
    else
        QSF_ClientState.accept(self.selected)
    end
end

-- this one moves the player across the map.
function QSF_Panel:onTeleport()
    self:ask("teleportModal", getText("IGUI_QSF_TeleportConfirm"), QSF_ClientState.teleport)
end

function QSF_Panel:onReload()
    QSF_ClientState.reload()
end

-- every global quest in the files, running or not: there is no taking one, so there is
-- nothing to sort them into.
function QSF_Panel:buildGlobalRows()
    local rows = {}

    for _, def in ipairs(QSF_ClientState.globalOrdered) do
        local run = QSF_ClientState.global[def.key]
        local active = run and run.status == "active"

        local row = {
            key = def.key,
            title = def.title,
            subtitle = QSF_Detail.runText(run),
            -- the row's own words for its colours: gold while it runs, green once it is
            -- won, and grey for one that ran out.
            status = active and "active" or (run and run.status == "completed" and "done") or nil,
            locked = run ~= nil and run.status == "expired",
        }

        if active then
            row.counter = QSF_Rules.sharedTally(def, run)
            row.progress = QSF_Rules.sharedOverall(def, run)
        end

        rows[#rows + 1] = row
    end

    return rows
end

function QSF_Panel:buildRows()
    if self:isGlobal() then return self:buildGlobalRows() end

    local rows = {}
    local counts = QSF_ClientState.counts()

    for _, def in ipairs(QSF_ClientState.ordered) do
        local rec = QSF_ClientState.record(def.key)
        local status = rec and rec.status or nil
        local state, reason, detail, extra = QSF_ClientState.stateOf(def, self.player)

        local wanted = false
        if self.tab == "active" then
            wanted = status == "active"
        elseif self.tab == "done" then
            wanted = status == "done"
        else
            -- not started, plus a repeatable back off cooldown. a hidden one does not even
            -- hint at itself, and one with a giver is found by going to them.
            wanted = (state == "available" or state == "locked") and not def.giver
        end

        if wanted then
            local locked = self.tab == "available" and state == "locked"
            local row = {
                key = def.key,
                title = def.title,
                status = status,
                locked = locked,
                subtitle = QSF_Location.describe(def.location),
            }

            if status == "active" then
                row.counter = QSF_Rules.tally(def, rec, counts)
                row.progress = QSF_Rules.overallProgress(def, rec, counts)
            elseif locked then
                row.subtitle = QSF_Detail.reasonText(reason, detail, extra) or row.subtitle
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

    -- a selection that fell out of the tab would leave the pane showing a missing row.
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
    if self.detail then self.detail:setKey(self.selected, self:isGlobal()) end

    self:updateAction()
end

function QSF_Panel:setAction(title, enabled)
    self.action:setTitle(getText(title))
    self.action:setEnable(enabled)
end

-- the one thing a player does to a global quest. greyed unless they are carrying something
-- it is still short of, by the same sum the server takes with.
function QSF_Panel:updateGlobalAction()
    local def, run = self:globalSelection()

    self:setAction("IGUI_QSF_Contribute", def ~= nil and QSF_Rules.givable(def, run, QSF_ClientState.counts()) > 0)

    if not self.globalRun then return end

    self.globalRun:setTitle(getText(run and run.status == "active" and "IGUI_QSF_GlobalEnd" or "IGUI_QSF_GlobalStart"))
    self.globalRun:setEnable(def ~= nil)
end

function QSF_Panel:updateAction()
    self:updateTeleport()

    if not self.action then return end

    if self:isGlobal() then
        self:updateGlobalAction()
        return
    end

    local def = self.selected and QSF_ClientState.defs[self.selected] or nil

    if not def then
        self:setAction("IGUI_QSF_Accept", false)
        return
    end

    local state = QSF_ClientState.stateOf(def, self.player)

    if state == "turnin" then
        -- still reads Turn In, greyed, rather than swapping to Abandon: the same spot on
        -- the same button throwing a finished quest away would be a trap. the pane says
        -- who to take it back to.
        self:setAction("IGUI_QSF_TurnIn", not def.giver)
    elseif state == "progress" then
        self:setAction("IGUI_QSF_Abandon", true)
    else
        -- the same answer the row greyed itself with. a giver quest only reaches this on
        -- Completed, as a repeatable that is ready again, and is taken from the giver.
        self:setAction("IGUI_QSF_Accept", state == "available" and not def.giver)
    end
end

-- only reachable on a quest the player is actually on, so it is hidden outright rather
-- than greyed on the Available and Completed tabs.
function QSF_Panel:updateTeleport()
    if not self.teleport then return end

    -- a global quest has its own keys, and one could spell a personal quest's.
    local key = not self:isGlobal() and self.selected or nil
    local def = key and QSF_ClientState.defs[key] or nil
    local rec = key and QSF_ClientState.record(key) or nil

    if not def or not def.teleport or not rec or rec.status ~= "active" then
        self.teleport:setVisible(false)
        return
    end

    self.teleport:setVisible(true)

    local ok, _, hours = QSF_Rules.canTeleport(def, rec)
    if ok then
        self.teleport:setTitle(getText("IGUI_QSF_Teleport"))
    else
        -- the refused toast is never drawn, so the wait has to be readable on the button.
        self.teleport:setTitle(getText("IGUI_QSF_TeleportCooldown", tostring(hours or 0)))
    end

    self.teleport:setEnable(ok == true)
end

function QSF_Panel:prerender()
    ISCollapsableWindow.prerender(self)

    local _, listY, footerY, listW = self:bands()
    local well, frame = QSF_Theme.COL_WELL, QSF_Theme.COL_FRAME

    self:drawRect(PAD, listY, listW, footerY - listY - GAP, well.a, well.r, well.g, well.b)
    self:drawRectBorder(PAD, listY, listW, footerY - listY - GAP, frame.a, frame.r, frame.g, frame.b)
    self:drawRect(PAD + listW + GAP / 2, listY, 1, footerY - listY - GAP, frame.a, frame.r, frame.g, frame.b)

    for _, button in pairs(self.tabs) do
        button.selected = self.tab == button.tab
    end

    -- a java call in a per-frame prerender, and it cannot change without a reconnect.
    if self.reload then
        if self.isAdmin == nil then self.isAdmin = QSF.isAdmin(self.player) end
        self.reload:setVisible(self.isAdmin)
        if self.globalRun then self.globalRun:setVisible(self.isAdmin and self:isGlobal()) end
    end
end

function QSF_Panel:render()
    ISCollapsableWindow.render(self)

    if #self.rows == 0 then
        local _, listY = self:bands()
        local text = QSF_ClientState.ready and getText("IGUI_QSF_Empty_" .. self.tab) or getText("IGUI_QSF_Connecting")
        QSF_Theme.text(self, text, PAD + 10, listY + 10, QSF_Theme.COL_DIM)
    end
end

function QSF_Panel:update()
    ISCollapsableWindow.update(self)

    -- the cache bumps a revision on anything from the server and the poll bumps it on a
    -- count change; the tick floor only backstops whatever moves without either.
    self.ticks = self.ticks + 1

    if self.revision ~= QSF_ClientState.revision then
        self.revision = QSF_ClientState.revision
        self.ticks = 0
        self:refresh()
    elseif self.ticks >= REFRESH_TICKS then
        self.ticks = 0

        -- a countdown moves with nothing arriving to say so, and it is written on the rows.
        -- every ten seconds is as fine as a line that counts in minutes can show.
        local beat = math.floor(getTimestampMs() / 10000)

        if self:isGlobal() and beat ~= self.beat then
            self.beat = beat
            self:refresh()
        else
            self:updateAction()
        end
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

    for _, button in ipairs({ self.action, self.teleport, self.reload, self.globalRun }) do
        button:setY(footerY + 2)
    end
end

function QSF_Panel:close()
    QSF_Choice.dismiss(self)

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
    local x, y = QSF_Theme.centre(width, height)

    -- back where it was last left, if it has been open before.
    data.instance = QSF_Theme.open(QSF_Panel:new(data.x or x, data.y or y, width, height, player))
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
