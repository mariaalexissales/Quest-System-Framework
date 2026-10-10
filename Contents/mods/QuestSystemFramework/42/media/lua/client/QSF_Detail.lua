----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "ISUI/ISRichTextPanel"
require "QSF_Theme"
require "QSF_Rules"
require "QSF_Location"
require "QSF_ClientState"
require "QSF_Text"

QSF_Detail = ISPanel:derive("QSF_Detail")

local PAD = 10
local GAP = 6
local ICON = 12
local MAX_OBJECTIVES = 8
local MAX_REWARDS = 6
local MAX_POOL = 6

-- how long the pane goes on drawing what it last worked out when nothing has arrived to
-- say it is wrong. what locks a quest moves with the clock, a skill and a kill count, and a
-- countdown moves by itself.
local BEAT_MS = 1000

function QSF_Detail:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.key = nil

    -- the dialogue turns both off: the npc is saying the description itself, and the
    -- player is already standing in front of who to go back to.
    o.showBody = true
    o.showGiver = true

    o.global = false

    -- everything the pane says, worked out once and drawn every frame until it is stale.
    o.lines = {}
    o.stale = true

    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }
    o.moveWithMouse = false

    o.titleHeight = getTextManager():getFontHeight(UIFont.Medium)
    o.lineHeight = getTextManager():getFontHeight(UIFont.Small)

    return o
end

function QSF_Detail:createChildren()
    ISPanel.createChildren(self)

    self.body = QSF_Theme.richText(self, PAD, 0, self.width - PAD * 2, 60)
end

-- global quests keep their own keys, so the key alone does not say which list it is from.
function QSF_Detail:setKey(key, global)
    global = global == true
    if self.key == key and self.global == global then return end

    self.key = key
    self.global = global
    self.stale = true
end

function QSF_Detail:def()
    if not self.key then return nil end
    if self.global then return QSF_ClientState.globalDefs[self.key] end
    return QSF_ClientState.defs[self.key]
end

-- have, need, satisfied. a global quest's are the server's counters, whatever the type.
function QSF_Detail:progressOf(obj, index, rec)
    if self.global then return QSF_Rules.sharedProgress(obj, index, rec) end
    return QSF_Rules.objectiveProgress(obj, index, rec, QSF_ClientState.counts())
end

function QSF_Detail:onResize()
    ISPanel.onResize(self)
    if self.body then
        self.body:setWidth(self.width - PAD * 2)
        self.stale = true
    end
end

-- why a quest cannot be taken, by the reason canAccept gave. these say it all by themselves.
local PLAIN = {
    MaxTurnins = "IGUI_QSF_MaxTurnins",
    AlreadyDone = "IGUI_QSF_AlreadyDone",
    NeedPick = "IGUI_QSF_NeedPick",
}

-- and these need the number that came with the reason.
local COUNTED = {
    NeedKills = "IGUI_QSF_NeedKills",
    NeedDays = "IGUI_QSF_NeedDays",
    OnCooldown = "IGUI_QSF_OnCooldown",
}

-- extra is the level, and only a skill has one. nil for a reason with no wording.
local function QSF_reasonText(reason, detail, extra)
    if reason == "NeedQuest" then
        local def = QSF_ClientState.defs[detail]
        return getText("IGUI_QSF_NeedQuest", def and def.title or tostring(detail))
    end

    if reason == "NeedSkill" then
        return getText("IGUI_QSF_NeedSkill", QSF_Theme.perkName(detail), tostring(extra))
    end

    if COUNTED[reason] then return getText(COUNTED[reason], tostring(detail)) end
    if PLAIN[reason] then return getText(PLAIN[reason]) end

    return nil
end

QSF_Detail.reasonText = QSF_reasonText

-- one line of the prerequisites, which sit under a heading that already says they are
-- required. a quest is named by its title.
local function QSF_prereqText(entry)
    if entry.reason == "NeedQuest" then
        local def = QSF_ClientState.defs[entry.detail]
        return def and def.title or tostring(entry.detail)
    end

    if entry.reason == "NeedSkill" then
        return getText("IGUI_QSF_Prereq_Skill", QSF_Theme.perkName(entry.detail), tostring(entry.extra))
    end

    if entry.reason == "NeedKills" then return getText("IGUI_QSF_Prereq_Kills", tostring(entry.detail)) end

    return getText("IGUI_QSF_Prereq_Days", tostring(entry.detail))
end

local MINUTE_MS = 60000

-- the two largest units, which is as exact as anybody planning their evening needs.
local function QSF_duration(ms)
    local minutes = math.max(1, math.ceil(ms / MINUTE_MS))
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)

    if days > 0 then return getText("IGUI_QSF_Dur_Days", tostring(days), tostring(hours % 24)) end
    if hours > 0 then return getText("IGUI_QSF_Dur_Hours", tostring(hours), tostring(minutes % 60)) end
    return getText("IGUI_QSF_Dur_Minutes", tostring(minutes))
end

-- where a global quest has got to, in a line. the row and the pane both say it.
local function QSF_runText(run)
    if not run then return getText("IGUI_QSF_Global_NotStarted") end
    if run.status == "completed" then return getText("IGUI_QSF_Global_Completed") end
    if run.status ~= "active" then return getText("IGUI_QSF_Global_Expired") end
    if not run.endsAt then return getText("IGUI_QSF_Global_Running") end

    return getText("IGUI_QSF_Global_Left", QSF_duration(run.endsAt - getTimestampMs()))
end

QSF_Detail.runText = QSF_runText

-- what an objective is called when the quest does not name it. anything else is an item.
local OBJECTIVE_LABELS = {
    kill = "IGUI_QSF_KillZombies",
    horde = "IGUI_QSF_SurviveHordes",
    hordeKill = "IGUI_QSF_KillHordeZombies",
}

function QSF_Detail:objectiveLabel(obj)
    local key = OBJECTIVE_LABELS[obj.type]
    if key then return getText(key) end

    return QSF_Theme.itemName(obj.item)
end

-- one thing to draw. icon is a tick or a cross, in the margin a line under a heading leaves.
function QSF_Detail:put(text, x, y, colour, font, icon)
    self.lines[#self.lines + 1] = { text = text, x = x, y = y, colour = colour, font = font, icon = icon }
end

-- each of these three returns the y the next thing goes on.
function QSF_Detail:heading(text, y)
    self:put(text, PAD, y, QSF_Theme.COL_TEXT)
    return y + self.lineHeight + 2
end

-- the full width of the pane, cut to fit it.
function QSF_Detail:wide(text, y, colour)
    self:put(QSF_Theme.truncate(text, self.width - PAD * 2, UIFont.Small), PAD, y, colour)
    return y + self.lineHeight
end

-- under a heading, set in past where a tick goes.
function QSF_Detail:line(text, y, colour, icon)
    self:put(QSF_Theme.truncate(text, self.width - PAD * 2 - ICON - GAP, UIFont.Small),
        PAD + ICON + GAP, y, colour, nil, icon)
    return y + self.lineHeight
end

-- drawn every frame, worked out about once a second: the names, the wording and the rules
-- behind a line are a dozen calls into the engine each, and almost never give a new answer.
function QSF_Detail:render()
    ISPanel.render(self)

    local beat = math.floor(getTimestampMs() / BEAT_MS)

    if self.stale or self.revision ~= QSF_ClientState.revision or self.beat ~= beat then
        self.stale = false
        self.revision = QSF_ClientState.revision
        self.beat = beat
        self:build()
    end

    for _, line in ipairs(self.lines) do
        if line.icon then self:drawTextureScaledAspect(line.icon, PAD, line.y + 1, ICON, ICON, 1, 1, 1, 1) end
        QSF_Theme.text(self, line.text, line.x, line.y, line.colour, line.font)
    end
end

-- top to bottom, each part handing the next the y it stopped at.
function QSF_Detail:build()
    self.lines = {}

    local def = self:def()

    if not def then
        self:put(getText(QSF_ClientState.ready and "IGUI_QSF_PickAQuest" or "IGUI_QSF_Connecting"),
            PAD, PAD, QSF_Theme.COL_DIM)
        if self.body then self.body:setVisible(false) end
        return
    end

    if self.body then self.body:setVisible(self.showBody) end

    -- a global quest's record is the server's run of it, not anything of the player's.
    local rec
    if self.global then rec = QSF_ClientState.global[self.key] else rec = QSF_ClientState.record(self.key) end

    local where = QSF_Location.describe(def.location)

    local y = self:addHeader(def, rec, where, PAD)
    y = self:addBody(def, y)
    y = self:addObjectives(def, rec, where, y)
    y = self:addRewards(def, y)

    -- nothing locks a global quest: it is running for everybody or for nobody.
    if not self.global then y = self:addLock(def, y) end

    -- how far down it got, for a window that has to make room for all of it.
    self.contentHeight = y + PAD
end

function QSF_Detail:addHeader(def, rec, where, y)
    self:put(QSF_Theme.truncate(def.title, self.width - PAD * 2, UIFont.Medium), PAD, y,
        QSF_Theme.COL_TITLE, UIFont.Medium)
    y = y + self.titleHeight + 2

    if where then y = self:wide(where, y, QSF_Theme.COL_COUNT) end

    -- a giver quest cannot be taken or handed in from here, so say where it can.
    local giver = self.showGiver and def.giver and QSF_ClientState.npcs[def.giver] or nil
    if giver then
        local active = rec and rec.status == "active"
        y = self:wide(getText(active and "IGUI_QSF_GiverReturn" or "IGUI_QSF_GiverOffer", giver.name), y,
            QSF_Theme.COL_COUNT)
    end

    if self.global then y = self:addRun(def, rec, y) end

    return y + GAP
end

-- how long is left, then who is in on it. the second line waits for somebody to be.
function QSF_Detail:addRun(def, run, y)
    y = self:wide(QSF_runText(run), y, QSF_Theme.COL_COUNT)

    if not run or (run.count or 0) == 0 then return y end

    local text = getText("IGUI_QSF_Global_Taking", tostring(run.count), tostring(run.mine or 0))

    -- only worth saying when one kill is not enough to be counted in.
    if (def.minContribution or 1) > 1 then
        text = text .. "  " .. getText("IGUI_QSF_Global_Minimum", tostring(def.minContribution))
    end

    return self:wide(text, y, QSF_Theme.COL_DIM)
end

-- the description, filled the way the giver would say it, so it reads the same here as it
-- did there. laying rich text out is the dear part, so that waits for the words or the
-- width to have changed.
function QSF_Detail:addBody(def, y)
    if not self.body or not self.showBody then return y end

    local giver = def.giver and QSF_ClientState.npcs[def.giver] or nil
    local text = QSF_Text.fill(def.description or "", QSF_Text.values(getPlayer(), giver, def))

    if text ~= self.bodyText or self.width ~= self.bodyWidth then
        self.bodyText, self.bodyWidth = text, self.width
        self.body:setText(text)
        self.body:paginate()
    end

    self.body:setY(y)
    return y + self.body:getHeight() + GAP
end

function QSF_Detail:addObjectives(def, rec, where, y)
    local textures = QSF_Theme.textures()
    local counts = QSF_ClientState.counts()

    y = self:heading(getText("IGUI_QSF_Objectives"), y)

    for i, obj in ipairs(def.objectives) do
        if i > MAX_OBJECTIVES then
            y = self:line("...", y, QSF_Theme.COL_DIM)
            break
        end

        local have, need, satisfied = self:progressOf(obj, i, rec)

        local label = obj.label or self:objectiveLabel(obj)
        local text = label .. "   " .. have .. "/" .. need

        -- the counter is everybody's, so what this player could add to it is said apart.
        local carrying = self.global and obj.type == "collect" and not satisfied and counts[obj.item] or 0
        if carrying > 0 then text = text .. "  " .. getText("IGUI_QSF_Global_Carrying", tostring(carrying)) end

        -- only when it differs from the quest's own, which is already under the title.
        local scope = obj.location and QSF_Location.describe(obj.location) or nil
        if scope and scope ~= where then text = text .. "  (" .. scope .. ")" end

        y = self:line(text, y, satisfied and QSF_Theme.COL_DONE or QSF_Theme.COL_TEXT,
            satisfied and textures.iconTrue or textures.iconFalse) + 2
    end

    return y + GAP
end

-- a global quest pays one of two things, and both are worth knowing going in: the rewards
-- for finishing it, and what taking part is worth if it ends short of that.
function QSF_Detail:addRewards(def, y)
    local after = self:addPayout(def.rewards, "IGUI_QSF_Rewards", y)

    if self.global and def.consolation then
        after = self:addPayout(def.consolation, "IGUI_QSF_Participation", after > y and after + GAP or after)
    end

    return after
end

-- a list of reward items, and "..." for whatever is past the room there is for them.
function QSF_Detail:addItems(items, limit, y)
    for i, entry in ipairs(items) do
        if i > limit then return self:line("...", y, QSF_Theme.COL_DIM) end
        y = self:line(QSF_Theme.itemLabel(entry), y, QSF_Theme.COL_COUNT)
    end

    return y
end

function QSF_Detail:addPayout(rewards, heading, y)
    rewards = rewards or {}

    local items = rewards.items or {}
    local choice, random = rewards.choice, rewards.random

    if not choice and not QSF_Rules.hasRewards(rewards) then return y end

    y = self:heading(getText(heading), y)
    y = self:addItems(items, MAX_REWARDS, y)

    -- by name, so the list reads the same every time it is worked out.
    for _, perkName in ipairs(QSF.sortedKeys(rewards.xp)) do
        y = self:line(getText("IGUI_QSF_RewardXp", QSF_Theme.perkName(perkName), tostring(rewards.xp[perkName])),
            y, QSF_Theme.COL_COUNT)
    end

    -- both pools are listed on Available too, so the player can see what is on offer
    -- before deciding whether the quest is worth taking: the one they will pick from, and
    -- the one that is picked for them.
    if choice then
        y = self:heading(choice.label or getText("IGUI_QSF_ChooseOne"), y + 2)
        y = self:addItems(choice.options, MAX_POOL, y)
    end

    if random then
        y = self:heading(random.label or getText("IGUI_QSF_RandomRewards"), y + 2)
        y = self:addItems(random.options, MAX_POOL, y)
    end

    return y
end

-- a player cannot act on "no" alone. a quest still to be taken lists everything it asks
-- for, met or not, so what is left to do is plain before and after. one already finished
-- has only the one thing in the way, and says that.
function QSF_Detail:addLock(def, y)
    local player = getPlayer()
    local textures = QSF_Theme.textures()
    local state, reason, detail, extra = QSF_ClientState.stateOf(def, player)

    if state == "turnin" or state == "progress" then return y end

    if state == "done" then
        local text = QSF_reasonText(reason, detail, extra)
        if not text then return y end

        y = self:heading(getText("IGUI_QSF_Locked"), y + GAP)
        return self:line(text, y, QSF_Theme.COL_DIM, textures.iconFalse)
    end

    local list = QSF_Rules.prereqList(def, player, QSF_ClientState.state)
    if #list == 0 then return y end

    y = self:heading(getText("IGUI_QSF_Prerequisites"), y + GAP)

    for _, entry in ipairs(list) do
        y = self:line(QSF_prereqText(entry), y, entry.met and QSF_Theme.COL_DONE or QSF_Theme.COL_TEXT,
            entry.met and textures.iconTrue or textures.iconFalse) + 2
    end

    return y
end
