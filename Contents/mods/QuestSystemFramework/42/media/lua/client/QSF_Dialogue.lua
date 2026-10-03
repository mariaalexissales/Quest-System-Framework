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

QSF = QSF or {}

QSF_Dialogue = ISCollapsableWindow:derive("QSF_Dialogue")

local WIDTH = 440
local HEIGHT = 520
local PAD = 12
local GAP = 8
local OPTION_HEIGHT = 26
local OPTION_GAP = 4
local BUTTON_HEIGHT = 24
local REACH_TICKS = 15

-- the list is laid out rather than scrolled, and this many still fit under a greeting
-- of a few lines.
local MAX_OPTIONS = 10

local TAGS = {
    turnin = "IGUI_QSF_TagReady",
    progress = "IGUI_QSF_TagActive",
    locked = "IGUI_QSF_TagLocked",
}

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
    o.options = {}
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

function QSF_Dialogue:createChildren()
    ISCollapsableWindow.createChildren(self)

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

function QSF_Dialogue:say(text)
    self.speech:setText(text or "")
    self.speech:paginate()
end

function QSF_Dialogue:clearOptions()
    for _, button in ipairs(self.options) do
        self:removeChild(button)
    end
    self.options = {}
end

-- what the list shows, sorted the way the log sorts. it follows the log's Available tab:
-- something in hand, something on offer, or something locked that is allowed to hint at
-- itself. finished and not repeatable has nothing left to say.
function QSF_Dialogue:entries()
    local out = {}
    local counts = QSF_ClientState.counts()

    for _, def in ipairs(QSF_Rules.npcQuests(self.npcKey, QSF_ClientState.ordered)) do
        local rec = QSF_ClientState.record(def.key)
        local status = rec and rec.status or nil
        local state = nil

        if status == "active" then
            state = QSF_Rules.isComplete(def, rec, counts) and "turnin" or "progress"
        elseif QSF_Rules.canAccept(def, rec, self.player, QSF_ClientState.state) then
            state = "available"
        elseif status ~= "done" and not (def.prereqs and def.prereqs.hidden) then
            state = "locked"
        end

        if state then
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

    local y = self.speech:getY() + self.speech:getHeight() + GAP * 2
    local width = self.width - PAD * 2

    for index, entry in ipairs(entries) do
        if index > MAX_OPTIONS then break end

        local title = entry.title
        if TAGS[entry.state] then title = title .. "  " .. getText(TAGS[entry.state]) end

        local button = QSF_Button:new(PAD, y, width, OPTION_HEIGHT,
            QSF_Theme.truncate(title, width - 24, UIFont.Small), self, QSF_Dialogue.onOption)
        button.questKey = entry.key
        -- the one worth walking back for is lit the way a picked row is.
        button.selected = entry.state == "turnin"
        self.options[#self.options + 1] = self:attach(button)

        y = y + OPTION_HEIGHT + OPTION_GAP
    end

    self.detail:setVisible(false)
    self.primary:setVisible(false)
    self.primaryAction = nil
    self.back:setTitle(getText("IGUI_QSF_Goodbye"))
end

function QSF_Dialogue:showQuest(def)
    local rec = QSF_ClientState.record(def.key)
    local lines = def.dialogue or {}
    local text, action = nil, nil

    if rec and rec.status == "active" then
        if QSF_Rules.isComplete(def, rec, QSF_ClientState.counts()) then
            text = lines.complete or getText("IGUI_QSF_Npc_Complete")
            action = "turnin"
        else
            text = lines.progress or getText("IGUI_QSF_Npc_Progress")
        end
    elseif QSF_Rules.canAccept(def, rec, self.player, QSF_ClientState.state) then
        -- a quest written before it had a giver still has its description to say.
        text = lines.offer or (def.description ~= "" and def.description) or getText("IGUI_QSF_Npc_Offer")
        action = "accept"
    else
        -- the pane underneath spells out what is missing.
        text = getText("IGUI_QSF_Npc_Locked")
    end

    self:say(text)

    local y = self.speech:getY() + self.speech:getHeight() + GAP
    self.detail:setY(y)
    self.detail:setHeight(math.max(0, self:footerY() - GAP - y))
    self.detail:setKey(def.key)
    self.detail:setVisible(true)

    self.primaryAction = action
    self.primary:setVisible(action ~= nil)
    if action then
        self.primary:setTitle(getText(action == "turnin" and "IGUI_QSF_TurnIn" or "IGUI_QSF_Accept"))
    end

    self.back:setTitle(getText("IGUI_QSF_Back"))
end

function QSF_Dialogue:refresh()
    local npc = QSF_ClientState.npcs[self.npcKey]
    if not npc then
        self:close()
        return
    end

    self:clearOptions()

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

-- the buttons are rebuilt by a refresh, and one of them is in the middle of being clicked
-- whenever these run. so they only mark the window, and update() redraws it a frame later.
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
