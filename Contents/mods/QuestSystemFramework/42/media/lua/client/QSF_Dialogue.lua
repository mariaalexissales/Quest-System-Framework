----------
--ESTRAL--
----------

require "ISUI/ISCollapsableWindow"
require "ISUI/ISRichTextPanel"
require "QSF_Button"
require "QSF_Detail"
require "QSF_Choice"
require "QSF_Theme"
require "QSF_ClientState"
require "QSF_Rules"
require "QSF_Text"
require "QSF_NpcClient"

QSF = QSF or {}

QSF_Dialogue = ISCollapsableWindow:derive("QSF_Dialogue")

local WIDTH = 400
local HEIGHT = 320
local PAD = 12
local GAP = 8
local OPTION_HEIGHT = 26
local OPTION_GAP = 4
local BUTTON_HEIGHT = 24
local REACH_TICKS = 15

-- the list scrolls, so it only ever asks the window for three rows. a greeting long enough
-- to leave it less makes the window taller instead.
local MIN_LIST = 3 * (OPTION_HEIGHT + OPTION_GAP) + OPTION_GAP

local TAGS = {
    turnin = "IGUI_QSF_TagReady",
    progress = "IGUI_QSF_TagActive",
    locked = "IGUI_QSF_TagLocked",
}

-- what the list shows. finished and not repeatable has nothing left to say, and a hidden
-- quest is not to hint at itself.
local LISTED = { turnin = true, progress = true, available = true, locked = true }

function QSF_Dialogue:new(x, y, player, npc)
    local o = ISCollapsableWindow:new(x, y, WIDTH, HEIGHT)
    setmetatable(o, self)
    self.__index = self

    o.player = player
    o.playerNum = player:getPlayerNum()
    o.npcKey = npc.key
    o.title = npc.name

    -- nil is the list of what the npc has to say. a key is one quest opened up.
    o.questKey = nil
    o.primaryAction = nil
    -- every line already spoken over the npc's head in this conversation.
    o.said = {}
    o.revision = -1
    o.stale = false
    o.ticks = 0
    o.resizable = false

    return o
end

function QSF_Dialogue:attach(button)
    button:initialise()
    button:instantiate()
    self:addChild(button)
    return button
end

-- the two footer buttons each swap between two labels, so they are sized for the wider
-- one and the strip never reflows.
local function QSF_labelWidth(button, ...)
    local widest = 0
    for _, key in ipairs({ ... }) do
        widest = math.max(widest, getTextManager():MeasureStringX(button.font, getText(key)))
    end
    return 28 + widest
end

function QSF_Dialogue:footerY()
    return self.height - PAD - BUTTON_HEIGHT
end

-- the quests on offer, however many there are. NeatUI's list builds only as many buttons
-- as fit and hands them round as it scrolls, so a button is whichever quest it was last
-- given.
function QSF_Dialogue:createList()
    self.list = NIVirtualScrollView:new(PAD, 0, self.width - PAD * 2, MIN_LIST)
    self.list:initialise()
    self.list:instantiate()
    -- setOnCreateItem after instantiate: createChildren already ran initializePool once
    -- with no callback set and quietly did nothing.
    self.list:setOnCreateItem(function()
        local button = QSF_Button:new(0, 0, self.list:getWidth(), OPTION_HEIGHT, "", self, QSF_Dialogue.onOption)
        -- the pool calls initialise for us but not instantiate.
        button:instantiate()
        return button
    end)
    self.list:setOnUpdateItem(function(button, entry)
        self:fillOption(button, entry)
    end)
    self.list:setConfig(OPTION_HEIGHT, OPTION_GAP)
    self:addChild(self.list)
end

function QSF_Dialogue:fillOption(button, entry)
    -- the scroll bar is drawn over the list's right edge, and only when there is
    -- something to scroll.
    local width = self.list:getWidth()
    local bar = self.list.vscroll
    if bar and (self.list.maxScrollOffset or 0) > 0 then width = width - bar:getWidth() - 2 end

    local title = entry.title
    if TAGS[entry.state] then title = title .. "  " .. getText(TAGS[entry.state]) end

    button:setWidth(width)
    button:setTitle(QSF_Theme.truncate(title, width - 24, UIFont.Small))
    button.questKey = entry.key
    -- the one worth walking back for is lit the way a picked row is.
    button.selected = entry.state == "turnin"
end

function QSF_Dialogue:createChildren()
    ISCollapsableWindow.createChildren(self)
    self:createList()

    -- rich text, so a greeting gets <LINE> and <RGB:> the way a description does.
    self.speech = ISRichTextPanel:new(PAD, self:titleBarHeight() + PAD, self.width - PAD * 2, 40)
    self.speech:initialise()
    self.speech.background = false
    self.speech.autosetheight = true
    self.speech.marginLeft = 0
    self.speech.marginRight = 0
    self.speech.marginTop = 0
    self:addChild(self.speech)

    -- the same pane the log uses, so objectives and rewards read the same in both.
    self.detail = QSF_Detail:new(2, 0, self.width - 4, 100)
    self.detail.showBody = false
    self.detail.showGiver = false
    self.detail:initialise()
    self.detail:instantiate()
    self:addChild(self.detail)

    local y = self:footerY()

    self.back = QSF_Button:new(0, y, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Goodbye"), self, QSF_Dialogue.onBack)
    self.back:setWidth(QSF_labelWidth(self.back, "IGUI_QSF_Goodbye", "IGUI_QSF_Back"))
    self.back:setX(self.width - PAD - self.back:getWidth())
    self:attach(self.back)

    self.primary = QSF_Button:new(0, y, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Accept"), self, QSF_Dialogue.onPrimary)
    self.primary:setWidth(QSF_labelWidth(self.primary, "IGUI_QSF_Accept", "IGUI_QSF_TurnIn"))
    self.primary:setX(self.back:getX() - 6 - self.primary:getWidth())
    self:attach(self.primary)

    self:refresh()
    self.revision = QSF_ClientState.revision
end

-- def is the quest being talked about, when there is one, for a line that names it.
function QSF_Dialogue:say(text, def)
    local npc = QSF_ClientState.npcs[self.npcKey]
    text = QSF_Text.fill(text or "", QSF_Text.values(self.player, npc, def))

    self.speech:setText(text)
    self.speech:paginate()

    -- over its head as well, but once: the window redraws the same line every time the
    -- player comes back to it, and nobody greets the same person twice in a minute.
    if not self.said[text] then
        self.said[text] = true
        QSF_NpcClient.say(self.npcKey, text)
    end
end


-- the window is as tall as what it is showing needs, and never shorter than it opens. the
-- list scrolls, so it asks for little. a quest's details do not, and need as much as the
-- pane took the last time it drew them.
function QSF_Dialogue:layout()
    local top = self.speech:getY() + self.speech:getHeight() + GAP
    local needed = self.questKey and (self.detail.contentHeight or 0) or MIN_LIST
    local height = math.max(HEIGHT, top + needed + GAP + BUTTON_HEIGHT + PAD)

    if height ~= self.height then
        self:setHeight(height)

        -- growing off the bottom of the screen would put the buttons out of reach.
        local screen = getCore():getScreenHeight()
        if self:getY() + height > screen then self:setY(math.max(0, screen - height)) end
    end

    local footer = self:footerY()
    self.back:setY(footer)
    self.primary:setY(footer)

    local room = math.max(0, footer - GAP - top)
    self.detail:setY(top)
    self.detail:setHeight(room)

    -- hidden while a quest is open, and its pool is thrown away and rebuilt by a
    -- reconfigure, so it is only told when its height has really moved.
    if self.questKey then return end

    self.list:setY(top)
    if self.list:getHeight() ~= room then
        self.list:setHeight(room)
        self.list:setConfig(OPTION_HEIGHT, OPTION_GAP)
    end
end

function QSF_Dialogue:stateOf(def)
    return QSF_Rules.questState(def, QSF_ClientState.record(def.key), self.player,
        QSF_ClientState.state, QSF_ClientState.counts())
end

-- sorted the way the log sorts.
function QSF_Dialogue:entries()
    local out = {}

    for _, def in ipairs(QSF_Rules.npcQuests(self.npcKey, QSF_ClientState.ordered)) do
        local state = self:stateOf(def)

        if LISTED[state] then
            out[#out + 1] = { key = def.key, title = def.title, state = state }
        end
    end

    return out
end

function QSF_Dialogue:showList(npc)
    local entries = self:entries()

    if #entries > 0 then
        self:say(npc.greeting or getText("IGUI_QSF_Npc_Greeting"))
    else
        self:say(getText("IGUI_QSF_Npc_Nothing"))
    end

    self.detail:setVisible(false)
    self.list:setVisible(true)
    self.primary:setVisible(false)
    self.primaryAction = nil
    self.back:setTitle(getText("IGUI_QSF_Goodbye"))

    self:layout()

    -- after the layout, so it knows how tall it is before it works out whether it scrolls.
    -- forced, because the list only hands its buttons new quests when the rows in view
    -- move, and a quest changing state leaves them where they were.
    self.list:setDataSource(entries, true)
end

function QSF_Dialogue:showQuest(def)
    local state = self:stateOf(def)
    local lines = def.dialogue or {}
    local text, action = nil, nil

    if state == "turnin" then
        text = lines.complete or getText("IGUI_QSF_Npc_Complete")
        action = "turnin"
    elseif state == "progress" then
        text = lines.progress or getText("IGUI_QSF_Npc_Progress")
    elseif state == "available" then
        -- a quest written before it had a giver still has its description to say.
        text = lines.offer or (def.description ~= "" and def.description) or getText("IGUI_QSF_Npc_Offer")
        action = "accept"
    else
        -- the pane underneath spells out what is missing.
        text = getText("IGUI_QSF_Npc_Locked")
    end

    self:say(text, def)

    self.list:setVisible(false)
    self.detail:setKey(def.key)
    self.detail:setVisible(true)

    self.primaryAction = action
    self.primary:setVisible(action ~= nil)
    if action then
        self.primary:setTitle(getText(action == "turnin" and "IGUI_QSF_TurnIn" or "IGUI_QSF_Accept"))
    end

    self.back:setTitle(getText("IGUI_QSF_Back"))

    self:layout()
end

function QSF_Dialogue:refresh()
    local npc = QSF_ClientState.npcs[self.npcKey]
    if not npc then
        self:close()
        return
    end

    -- a reload can take the open quest away, or hand it to somebody else.
    local def = self.questKey and QSF_ClientState.defs[self.questKey] or nil
    if not def or def.giver ~= self.npcKey then
        self.questKey = nil
        def = nil
    end

    if def then
        self:showQuest(def)
    else
        self:showList(npc)
    end
end

-- the list hands its buttons new quests on a refresh, and one of them is in the middle of
-- being clicked whenever these run. so they only mark the window, and update() redraws it
-- a frame later.
function QSF_Dialogue:show(questKey)
    self.questKey = questKey
    self.stale = true
end

function QSF_Dialogue:onOption(button)
    self:show(button.questKey)
end

function QSF_Dialogue:onBack()
    if not self.questKey then
        self:close()
        return
    end

    self:show(nil)
end

function QSF_Dialogue:onPrimary()
    local key = self.questKey
    local def = key and QSF_ClientState.defs[key] or nil
    if not def then return end

    if self.primaryAction == "accept" then
        QSF_ClientState.accept(key)
    elseif self.primaryAction == "turnin" then
        if def.rewards and def.rewards.choice then
            -- guarded the way the log guards it: a second press would stack a second picker.
            if self.choiceModal then return end
            self.choiceModal = QSF_Choice.show(def, key, self, QSF_Dialogue.onConfirmChoice)
            return
        end
        QSF_ClientState.claim(key)
    else
        return
    end

    -- back to the list. the server's answer redraws it with the quest where it now belongs.
    self:show(nil)
end

function QSF_Dialogue:onConfirmChoice(key, pick)
    self.choiceModal = nil
    if not key or not pick then return end

    QSF_ClientState.claim(key, pick)
    self:show(nil)
end

function QSF_Dialogue:onCancelChoice()
    self.choiceModal = nil
end

function QSF_Dialogue:update()
    ISCollapsableWindow.update(self)

    if self.stale or self.revision ~= QSF_ClientState.revision then
        self.stale = false
        self.revision = QSF_ClientState.revision
        self:refresh()
    end

    -- the pane only knows how tall a quest is once it has drawn it, a frame after it was
    -- asked to. the window catches up here.
    if self.questKey and self.detail.contentHeight ~= self.fitted then
        self.fitted = self.detail.contentHeight
        self:layout()
    end

    -- the server refuses anything asked from out of reach, so a window left open by
    -- somebody walking away would only be a list of buttons that do nothing.
    self.ticks = self.ticks + 1
    if self.ticks < REACH_TICKS then return end
    self.ticks = 0

    local npc = QSF_ClientState.npcs[self.npcKey]
    if not npc or self.player:isDead() or not QSF_Rules.inReach(self.player, npc) then
        self:close()
    end
end

function QSF_Dialogue:close()
    -- the picker is a top-level window, so it would otherwise outlive the conversation.
    if self.choiceModal then
        self.choiceModal:close()
        self.choiceModal = nil
    end

    if QSF_Dialogue.instance == self then QSF_Dialogue.instance = nil end

    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
end

-- one conversation at a time. opening a second npc closes the first.
function QSF_Dialogue.open(player, npcKey)
    local npc = QSF_ClientState.npcs[npcKey]
    if not player or not npc then return end

    if QSF_Dialogue.instance then QSF_Dialogue.instance:close() end

    local x = (getCore():getScreenWidth() - WIDTH) / 2
    local y = (getCore():getScreenHeight() - HEIGHT) / 2

    local window = QSF_Dialogue:new(x, y, player, npc)
    window:initialise()
    window:instantiate()
    window:addToUIManager()
    window:bringToTop()

    QSF_Dialogue.instance = window
end
