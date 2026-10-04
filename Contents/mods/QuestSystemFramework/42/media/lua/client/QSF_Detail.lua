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
local MAX_CHOICE = 6

function QSF_Detail:new(x, y, width, height)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.key = nil

    -- the dialogue turns both off: the npc is saying the description itself, and the
    -- player is already standing in front of who to go back to.
    o.showBody = true
    o.showGiver = true

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

function QSF_Detail:setKey(key)
    if self.key == key then return end
    self.key = key
    self.bodyDirty = true
end

function QSF_Detail:refreshBody(def)
    if not self.bodyDirty or not self.body then return end
    self.bodyDirty = false

    -- filled the way the giver would say it, so it reads the same here as it did there.
    local giver = def and def.giver and QSF_ClientState.npcs[def.giver] or nil
    local text = QSF_Text.fill(def and def.description or "", QSF_Text.values(getPlayer(), giver, def))

    self.body:setText(text)
    self.body:paginate()

end

function QSF_Detail:onResize()
    ISPanel.onResize(self)
    if self.body then
        self.body:setWidth(self.width - PAD * 2)
        self.bodyDirty = true
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

-- one line under a heading, set in past where a tick goes.
function QSF_Detail:line(text, y, colour)
    QSF_Theme.text(self, QSF_Theme.truncate(text, self.width - PAD * 2 - ICON - GAP, UIFont.Small),
        PAD + ICON + GAP, y, colour)
end

function QSF_Detail:tick(texture, y)
    if texture then self:drawTextureScaledAspect(texture, PAD, y + 1, ICON, ICON, 1, 1, 1, 1) end
end

-- top to bottom, each part handing the next the y it stopped at.
function QSF_Detail:render()
    ISPanel.render(self)

    local def = self.key and QSF_ClientState.defs[self.key] or nil

    if not def then
        local text = QSF_ClientState.ready and getText("IGUI_QSF_PickAQuest") or getText("IGUI_QSF_Connecting")
        QSF_Theme.text(self, text, PAD, PAD, QSF_Theme.COL_DIM)
        if self.body then self.body:setVisible(false) end
        return
    end

    if self.body then self.body:setVisible(self.showBody) end

    local rec = QSF_ClientState.record(self.key)
    local where = QSF_Location.describe(def.location)

    local y = self:drawHeader(def, rec, where, PAD)
    y = self:drawBody(def, y)
    y = self:drawObjectives(def, rec, where, y)
    y = self:drawRewards(def, y)
    y = self:drawLock(def, rec, y)

    -- how far down it got, for a window that has to make room for all of it.
    self.contentHeight = y + PAD
end

function QSF_Detail:drawHeader(def, rec, where, y)
    local title = QSF_Theme.truncate(def.title, self.width - PAD * 2, UIFont.Medium)
    QSF_Theme.text(self, title, PAD, y, QSF_Theme.COL_TITLE, UIFont.Medium)
    y = y + self.titleHeight + 2

    if where then
        QSF_Theme.text(self, where, PAD, y, QSF_Theme.COL_COUNT)
        y = y + self.lineHeight
    end

    -- a giver quest cannot be taken or handed in from here, so say where it can.
    local giver = self.showGiver and def.giver and QSF_ClientState.npcs[def.giver] or nil
    if giver then
        local active = rec and rec.status == "active"
        local text = getText(active and "IGUI_QSF_GiverReturn" or "IGUI_QSF_GiverOffer", giver.name)
        QSF_Theme.text(self, QSF_Theme.truncate(text, self.width - PAD * 2, UIFont.Small), PAD, y,
            QSF_Theme.COL_COUNT)
        y = y + self.lineHeight
    end

    return y + GAP
end

function QSF_Detail:drawBody(def, y)
    self:refreshBody(def)
    if not self.body or not self.showBody then return y end

    self.body:setY(y)
    return y + self.body:getHeight() + GAP
end

function QSF_Detail:drawObjectives(def, rec, where, y)
    local textures = QSF_Theme.textures()
    local counts = QSF_ClientState.counts()

    QSF_Theme.text(self, getText("IGUI_QSF_Objectives"), PAD, y, QSF_Theme.COL_TEXT)
    y = y + self.lineHeight + 2

    for i, obj in ipairs(def.objectives) do
        if i > MAX_OBJECTIVES then
            self:line("...", y, QSF_Theme.COL_DIM)
            y = y + self.lineHeight
            break
        end

        local have, need, satisfied = QSF_Rules.objectiveProgress(obj, i, rec, counts)
        self:tick(satisfied and textures.iconTrue or textures.iconFalse, y)

        local label = obj.label or self:objectiveLabel(obj)
        local text = label .. "   " .. have .. "/" .. need

        -- only when it differs from the quest's own, which is already under the title.
        local scope = obj.location and QSF_Location.describe(obj.location) or nil
        if scope and scope ~= where then text = text .. "  (" .. scope .. ")" end

        self:line(text, y, satisfied and QSF_Theme.COL_DONE or QSF_Theme.COL_TEXT)
        y = y + self.lineHeight + 2
    end

    return y + GAP
end

function QSF_Detail:drawRewards(def, y)
    local rewards = def.rewards or {}
    local items = rewards.items or {}
    local choice = rewards.choice

    if #items == 0 and not choice and not rewards.xp then return y end

    QSF_Theme.text(self, getText("IGUI_QSF_Rewards"), PAD, y, QSF_Theme.COL_TEXT)
    y = y + self.lineHeight + 2

    for i, entry in ipairs(items) do
        if i > MAX_REWARDS then break end
        y = self:drawRewardLine(entry, y)
    end

    for perkName, amount in pairs(rewards.xp or {}) do
        local text = getText("IGUI_QSF_RewardXp", QSF_Theme.perkName(perkName), tostring(amount))
        QSF_Theme.text(self, text, PAD + ICON + GAP, y, QSF_Theme.COL_COUNT)
        y = y + self.lineHeight
    end

    -- the pool is drawn on Available too, so the player can see what is on offer before
    -- deciding whether the quest is worth taking.
    if choice then
        y = y + 2
        QSF_Theme.text(self, choice.label or getText("IGUI_QSF_ChooseOne"), PAD, y, QSF_Theme.COL_TEXT)
        y = y + self.lineHeight + 2

        for i, entry in ipairs(choice.options) do
            if i > MAX_CHOICE then
                self:line("...", y, QSF_Theme.COL_DIM)
                y = y + self.lineHeight
                break
            end
            y = self:drawRewardLine(entry, y)
        end
    end

    return y
end

-- a player cannot act on "no" alone.
function QSF_Detail:drawLock(def, rec, y)
    local ok, reason, detail, extra = QSF_Rules.canAccept(def, rec, getPlayer(), QSF_ClientState.state)
    if ok or reason == "AlreadyActive" then return y end

    local text = QSF_reasonText(reason, detail, extra)
    if not text then return y end

    y = y + GAP
    QSF_Theme.text(self, getText("IGUI_QSF_Locked"), PAD, y, QSF_Theme.COL_TEXT)
    y = y + self.lineHeight + 2

    self:tick(QSF_Theme.textures().iconFalse, y)
    self:line(text, y, QSF_Theme.COL_DIM)

    return y + self.lineHeight
end

function QSF_Detail:drawRewardLine(entry, y)
    local name = QSF_Theme.itemName(entry.item)
    local text = entry.count > 1 and (name .. " x" .. entry.count) or name

    self:line(text, y, QSF_Theme.COL_COUNT)

    return y + self.lineHeight
end

function QSF_Detail:objectiveLabel(obj)
    if obj.type == "kill" then
        return getText("IGUI_QSF_KillZombies")
    end

    return QSF_Theme.itemName(obj.item)
end
