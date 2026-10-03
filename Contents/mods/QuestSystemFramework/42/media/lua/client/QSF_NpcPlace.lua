----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "ISUI/ISTextEntryBox"
require "ISUI/ISComboBox"
require "ISUI/ISTickBox"
require "QSF_Button"
require "QSF_Theme"
require "QSF_Net"
require "QSF_ClientState"

QSF = QSF or {}

-- the admin's form for standing a new npc on a tile. everything it sends is checked again
-- by the server, which is the one that writes the file.
QSF_NpcPlace = ISPanel:derive("QSF_NpcPlace")

local WIDTH = 380
local PAD = 12
local GAP = 8
local ROW = 24
local LABEL = 76
local BUTTON_HEIGHT = 24
local SKINS = 5

-- the same pattern the schema holds a key to.
local VALID_KEY = "^[%w_%.%-]+$"

local ROWS = { "Key", "Name", "Outfit", "Female", "Skin", "Greeting" }

function QSF_NpcPlace:new(x, y, playerNum, tileX, tileY, tileZ)
    local headerHeight = getTextManager():getFontHeight(UIFont.Medium)
    local lineHeight = getTextManager():getFontHeight(UIFont.Small)

    -- header, the tile, one row a field, a line for whatever is wrong, the buttons.
    local height = PAD + headerHeight + 2 + lineHeight + GAP
        + #ROWS * (ROW + GAP)
        + lineHeight + GAP + BUTTON_HEIGHT + PAD

    local o = ISPanel:new(x, y, WIDTH, height)
    setmetatable(o, self)
    self.__index = self

    o.playerNum = playerNum
    o.tileX, o.tileY, o.tileZ = tileX, tileY, tileZ
    o.headerHeight = headerHeight
    o.lineHeight = lineHeight
    o.problem = nil
    o.rowY = {}

    o.backgroundColor = { r = 0.05, g = 0.05, b = 0.05, a = 0.95 }
    o.borderColor = QSF_Theme.COL_FRAME
    o.moveWithMouse = true

    return o
end

function QSF_NpcPlace:attach(child)
    child:initialise()
    child:instantiate()
    self:addChild(child)
    return child
end

function QSF_NpcPlace:createChildren()
    ISPanel.createChildren(self)

    local x = PAD + LABEL
    local width = self.width - PAD - x
    local y = PAD + self.headerHeight + 2 + self.lineHeight + GAP

    local function nextRow(name)
        self.rowY[name] = y
        local at = y
        y = y + ROW + GAP
        return at
    end

    self.key = self:attach(ISTextEntryBox:new("", x, nextRow("Key"), width, ROW))
    self.name = self:attach(ISTextEntryBox:new("", x, nextRow("Name"), width, ROW))

    -- every outfit either gender has, the way the vanilla horde tool lists them. typing
    -- in the box narrows it, which two hundred names need.
    self.outfit = self:attach(ISComboBox:new(x, nextRow("Outfit"), width, ROW))
    self.outfit:setEditable(true)

    self.maleOutfits = getAllOutfits(false)
    self.femaleOutfits = getAllOutfits(true)

    for i = 0, self.maleOutfits:size() - 1 do
        local outfit = self.maleOutfits:get(i)
        local label = outfit
        if not self.femaleOutfits:contains(outfit) then
            label = label .. " - " .. getText("IGUI_SpawnHorde_MaleOnly")
        end
        self.outfit:addOptionWithData(label, outfit)
    end
    for i = 0, self.femaleOutfits:size() - 1 do
        local outfit = self.femaleOutfits:get(i)
        if not self.maleOutfits:contains(outfit) then
            self.outfit:addOptionWithData(outfit .. " - " .. getText("IGUI_SpawnHorde_FemaleOnly"), outfit)
        end
    end
    self.outfit:selectData("Generic01")

    self.female = self:attach(ISTickBox:new(x, nextRow("Female"), width, ROW, "", self, QSF_NpcPlace.onChanged))
    self.female:addOption("")

    self.skin = self:attach(ISComboBox:new(x, nextRow("Skin"), 60, ROW))
    for index = 1, SKINS do
        self.skin:addOptionWithData(tostring(index), index)
    end

    self.greeting = self:attach(ISTextEntryBox:new("", x, nextRow("Greeting"), width, ROW))

    local buttonY = self.height - PAD - BUTTON_HEIGHT

    self.cancel = QSF_Button:new(0, buttonY, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Cancel"), self, QSF_NpcPlace.onCancel)
    self.cancel:sizeToTitle(28)
    self.cancel:setX(self.width - PAD - self.cancel:getWidth())
    self:attach(self.cancel)

    self.confirm = QSF_Button:new(0, buttonY, 10, BUTTON_HEIGHT, getText("IGUI_QSF_Confirm"), self, QSF_NpcPlace.onOk)
    self.confirm:sizeToTitle(28)
    self.confirm:setX(self.cancel:getX() - 6 - self.confirm:getWidth())
    self:attach(self.confirm)
end

-- anything that was wrong may not be any more.
function QSF_NpcPlace:onChanged()
    self.problem = nil
end

-- gsub hands back a count as well, which is why neither of these returns it directly.
local function QSF_trim(text)
    local out = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    return out
end

-- "Old Joe" becomes old_joe, so an admin who only wants to name somebody does not have to
-- think of a key as well.
local function QSF_keyFromName(name)
    local key = name:lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return key
end

-- returns the entry to send, or nil and the translation key of what is wrong with it.
function QSF_NpcPlace:collect()
    local name = QSF_trim(self.name:getText())
    local key = QSF_trim(self.key:getText())
    if key == "" then key = QSF_keyFromName(name) end

    if key == "" or not key:match(VALID_KEY) then return nil, "IGUI_QSF_Place_BadKey" end
    if QSF_ClientState.npcs[key] then return nil, "IGUI_QSF_Place_KeyTaken" end

    local female = self.female:isSelected(1)
    local outfit = self.outfit:getOptionData(self.outfit.selected)
    local list = female and self.femaleOutfits or self.maleOutfits

    if not outfit or not list:contains(outfit) then
        return nil, female and "IGUI_QSF_Place_MaleOutfit" or "IGUI_QSF_Place_FemaleOutfit"
    end

    local greeting = QSF_trim(self.greeting:getText())

    return {
        key = key,
        name = name ~= "" and name or key,
        x = self.tileX,
        y = self.tileY,
        z = self.tileZ,
        outfit = outfit,
        female = female,
        skin = self.skin:getOptionData(self.skin.selected) or 1,
        greeting = greeting ~= "" and greeting or nil,
    }
end

function QSF_NpcPlace:onOk()
    local entry, problem = self:collect()
    if not entry then
        self.problem = problem
        return
    end

    QSF_Net.toServer("npcPlace", entry)
    self:close()
end

function QSF_NpcPlace:onCancel()
    self:close()
end

function QSF_NpcPlace:close()
    if QSF_NpcPlace.instance == self then QSF_NpcPlace.instance = nil end

    self:setVisible(false)
    self:removeFromUIManager()
end

function QSF_NpcPlace:render()
    ISPanel.render(self)

    self:drawText(getText("IGUI_QSF_Place_Title"), PAD, PAD,
        QSF_Theme.COL_TITLE.r, QSF_Theme.COL_TITLE.g, QSF_Theme.COL_TITLE.b, 1, UIFont.Medium)

    -- the tile, written the way it would be in a file, for whoever copies it into one.
    self:drawText(self.tileX .. ", " .. self.tileY .. ", " .. self.tileZ, PAD, PAD + self.headerHeight + 2,
        QSF_Theme.COL_COUNT.r, QSF_Theme.COL_COUNT.g, QSF_Theme.COL_COUNT.b, 1, UIFont.Small)

    local nudge = (ROW - self.lineHeight) / 2
    for _, name in ipairs(ROWS) do
        self:drawText(getText("IGUI_QSF_Field_" .. name), PAD, self.rowY[name] + nudge,
            QSF_Theme.COL_TEXT.r, QSF_Theme.COL_TEXT.g, QSF_Theme.COL_TEXT.b, 1, UIFont.Small)
    end

    if self.problem then
        local y = self.height - PAD - BUTTON_HEIGHT - GAP - self.lineHeight
        self:drawText(QSF_Theme.truncate(getText(self.problem), self.width - PAD * 2, UIFont.Small), PAD, y,
            QSF_Theme.COL_ACTIVE.r, QSF_Theme.COL_ACTIVE.g, QSF_Theme.COL_ACTIVE.b, 1, UIFont.Small)
    end
end

-- one form at a time. asking for a second tile moves the form to it.
function QSF_NpcPlace.show(playerNum, tileX, tileY, tileZ)
    if QSF_NpcPlace.instance then QSF_NpcPlace.instance:close() end

    -- the height is worked out by new(), so it is centred once there is one to centre.
    local form = QSF_NpcPlace:new(0, 0, playerNum, tileX, tileY, tileZ)
    form:initialise()
    form:instantiate()
    form:setX((getCore():getScreenWidth() - form:getWidth()) / 2)
    form:setY((getCore():getScreenHeight() - form:getHeight()) / 2)
    form:addToUIManager()
    form:bringToTop()

    QSF_NpcPlace.instance = form
    return form
end
