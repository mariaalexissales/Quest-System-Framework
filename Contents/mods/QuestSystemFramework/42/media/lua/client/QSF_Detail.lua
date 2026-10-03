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

    -- rich text gives admins <LINE> and <RGB:> in a description for free.
    self.body = ISRichTextPanel:new(PAD, 0, self.width - PAD * 2, 60)
    self.body:initialise()
    self.body.background = false
    self.body.autosetheight = true
    self.body.marginLeft = 0
    self.body.marginRight = 0
    self.body.marginTop = 0
    self:addChild(self.body)
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

-- extra is the level, and only a skill has one.
local function QSF_reasonText(reason, detail, extra)
    if reason == "NeedQuest" then
        local def = QSF_ClientState.defs[detail]
        return getText("IGUI_QSF_NeedQuest", def and def.title or tostring(detail))
    elseif reason == "NeedSkill" then
        return getText("IGUI_QSF_NeedSkill", QSF_Theme.perkName(detail), tostring(extra))
    elseif reason == "NeedKills" then
        return getText("IGUI_QSF_NeedKills", tostring(detail))
    elseif reason == "NeedDays" then
        return getText("IGUI_QSF_NeedDays", tostring(detail))
    elseif reason == "OnCooldown" then
        return getText("IGUI_QSF_OnCooldown", tostring(detail))
    elseif reason == "MaxTurnins" then
        return getText("IGUI_QSF_MaxTurnins")
    elseif reason == "AlreadyDone" then
        return getText("IGUI_QSF_AlreadyDone")
    elseif reason == "NeedPick" then
        return getText("IGUI_QSF_NeedPick")
    end
    return nil
end

QSF_Detail.reasonText = QSF_reasonText

function QSF_Detail:render()
    ISPanel.render(self)

    local def = self.key and QSF_ClientState.defs[self.key] or nil

    if not def then
        local text = QSF_ClientState.ready and getText("IGUI_QSF_PickAQuest") or getText("IGUI_QSF_Connecting")
        self:drawText(text, PAD, PAD, QSF_Theme.COL_DIM.r, QSF_Theme.COL_DIM.g, QSF_Theme.COL_DIM.b, 1, UIFont.Small)
        if self.body then self.body:setVisible(false) end
        return
    end

    if self.body then self.body:setVisible(self.showBody) end

    local rec = QSF_ClientState.record(self.key)
    local counts = QSF_ClientState.counts()
    local y = PAD

    local title = QSF_Theme.truncate(def.title, self.width - PAD * 2, UIFont.Medium)
    self:drawText(title, PAD, y, QSF_Theme.COL_TITLE.r, QSF_Theme.COL_TITLE.g, QSF_Theme.COL_TITLE.b, 1, UIFont.Medium)
    y = y + self.titleHeight + 2

    local where = QSF_Location.describe(def.location)
    if where then
        self:drawText(where, PAD, y, QSF_Theme.COL_COUNT.r, QSF_Theme.COL_COUNT.g, QSF_Theme.COL_COUNT.b, 1, UIFont.Small)
        y = y + self.lineHeight
    end

    -- a giver quest cannot be taken or handed in from here, so say where it can.
    local giver = self.showGiver and def.giver and QSF_ClientState.npcs[def.giver] or nil
    if giver then
        local active = rec and rec.status == "active"
        local text = getText(active and "IGUI_QSF_GiverReturn" or "IGUI_QSF_GiverOffer", giver.name)
        self:drawText(QSF_Theme.truncate(text, self.width - PAD * 2, UIFont.Small), PAD, y,
            QSF_Theme.COL_COUNT.r, QSF_Theme.COL_COUNT.g, QSF_Theme.COL_COUNT.b, 1, UIFont.Small)
        y = y + self.lineHeight
    end

    y = y + GAP

    self:refreshBody(def)
    if self.body and self.showBody then
        self.body:setY(y)
        y = y + self.body:getHeight() + GAP
    end

    local textures = QSF_Theme.textures()

    self:drawText(getText("IGUI_QSF_Objectives"), PAD, y,
        QSF_Theme.COL_TEXT.r, QSF_Theme.COL_TEXT.g, QSF_Theme.COL_TEXT.b, 1, UIFont.Small)
    y = y + self.lineHeight + 2

    for i, obj in ipairs(def.objectives) do
        if i > MAX_OBJECTIVES then
            self:drawText("...", PAD + ICON + GAP, y, QSF_Theme.COL_DIM.r, QSF_Theme.COL_DIM.g, QSF_Theme.COL_DIM.b, 1, UIFont.Small)
            y = y + self.lineHeight
            break
        end

        local have, need, satisfied = QSF_Rules.objectiveProgress(obj, i, rec, counts)
        local icon = satisfied and textures.iconTrue or textures.iconFalse

        if icon then
            self:drawTextureScaledAspect(icon, PAD, y + 1, ICON, ICON, 1, 1, 1, 1)
        end

        local col = satisfied and QSF_Theme.COL_DONE or QSF_Theme.COL_TEXT
        local label = obj.label or self:objectiveLabel(obj)
        local text = label .. "   " .. have .. "/" .. need

        local scope = obj.location and QSF_Location.describe(obj.location) or nil
        if scope and scope ~= where then text = text .. "  (" .. scope .. ")" end

        self:drawText(QSF_Theme.truncate(text, self.width - PAD * 2 - ICON - GAP, UIFont.Small),
            PAD + ICON + GAP, y, col.r, col.g, col.b, 1, UIFont.Small)
        y = y + self.lineHeight + 2
    end

    y = y + GAP

    local rewards = def.rewards and def.rewards.items or {}
    local choice = def.rewards and def.rewards.choice or nil

    if #rewards > 0 or choice or (def.rewards and def.rewards.xp) then
        self:drawText(getText("IGUI_QSF_Rewards"), PAD, y,
            QSF_Theme.COL_TEXT.r, QSF_Theme.COL_TEXT.g, QSF_Theme.COL_TEXT.b, 1, UIFont.Small)
        y = y + self.lineHeight + 2

        for i, entry in ipairs(rewards) do
            if i > MAX_REWARDS then break end
            y = self:drawRewardLine(entry, y)
        end

        for perkName, amount in pairs(def.rewards.xp or {}) do
            local text = getText("IGUI_QSF_RewardXp", QSF_Theme.perkName(perkName), tostring(amount))
            self:drawText(text, PAD + ICON + GAP, y,
                QSF_Theme.COL_COUNT.r, QSF_Theme.COL_COUNT.g, QSF_Theme.COL_COUNT.b, 1, UIFont.Small)
            y = y + self.lineHeight
        end

        -- the pool is drawn on Available too, so the player can see what is on offer
        -- before deciding whether the quest is worth taking.
        if choice then
            y = y + 2
            self:drawText(choice.label or getText("IGUI_QSF_ChooseOne"), PAD, y,
                QSF_Theme.COL_TEXT.r, QSF_Theme.COL_TEXT.g, QSF_Theme.COL_TEXT.b, 1, UIFont.Small)
            y = y + self.lineHeight + 2

            for i, entry in ipairs(choice.options) do
                if i > MAX_CHOICE then
                    self:drawText("...", PAD + ICON + GAP, y,
                        QSF_Theme.COL_DIM.r, QSF_Theme.COL_DIM.g, QSF_Theme.COL_DIM.b, 1, UIFont.Small)
                    y = y + self.lineHeight
                    break
                end
                y = self:drawRewardLine(entry, y)
            end
        end
    end

    -- a player cannot act on "no" alone.
    local ok, reason, detail, extra = QSF_Rules.canAccept(def, rec, getPlayer(), QSF_ClientState.state)
    if not ok and reason ~= "AlreadyActive" then
        local text = QSF_reasonText(reason, detail, extra)
        if text then
            y = y + GAP
            self:drawText(getText("IGUI_QSF_Locked"), PAD, y,
                QSF_Theme.COL_TEXT.r, QSF_Theme.COL_TEXT.g, QSF_Theme.COL_TEXT.b, 1, UIFont.Small)
            y = y + self.lineHeight + 2

            if textures.iconFalse then
                self:drawTextureScaledAspect(textures.iconFalse, PAD, y + 1, ICON, ICON, 1, 1, 1, 1)
            end
            self:drawText(QSF_Theme.truncate(text, self.width - PAD * 2 - ICON - GAP, UIFont.Small),
                PAD + ICON + GAP, y, QSF_Theme.COL_DIM.r, QSF_Theme.COL_DIM.g, QSF_Theme.COL_DIM.b, 1, UIFont.Small)
        end
    end
end

function QSF_Detail:drawRewardLine(entry, y)
    local name = QSF_Theme.itemName(entry.item)
    local text = entry.count > 1 and (name .. " x" .. entry.count) or name

    self:drawText(QSF_Theme.truncate(text, self.width - PAD * 2 - ICON - GAP, UIFont.Small),
        PAD + ICON + GAP, y, QSF_Theme.COL_COUNT.r, QSF_Theme.COL_COUNT.g, QSF_Theme.COL_COUNT.b, 1, UIFont.Small)

    return y + self.lineHeight
end

function QSF_Detail:objectiveLabel(obj)
    if obj.type == "kill" then
        return getText("IGUI_QSF_KillZombies")
    end

    return QSF_Theme.itemName(obj.item)
end
