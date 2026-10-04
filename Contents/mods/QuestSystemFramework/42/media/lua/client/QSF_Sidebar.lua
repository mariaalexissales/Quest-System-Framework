----------
--ESTRAL--
----------

require "QSF_Panel"

-- ISEquippedItem keeps TEXTURE_WIDTH file-local, so the scale is derived again here.
-- size 6 means "match the font size" and resolves through a different option.
local function QSF_textureWidth()
    local size = getCore():getOptionSidebarSize()
    if size == 6 then
        size = getCore():getOptionFontSizeReal() - 1
    end

    if size == 2 then return 64 end
    if size == 3 then return 80 end
    if size == 4 then return 96 end
    if size == 5 then return 128 end
    return 48
end

-- the sidebar is rebuilt wholesale when the size option changes, leaving the old panel
-- alive for a frame or two. touching a stale one corrupts the live panel's geometry.
local function QSF_isCurrentPanel(panel)
    if not panel or not panel.playerNum then return false end

    local playerData = getPlayerData(panel.playerNum)
    if playerData and playerData.equipped and playerData.equipped ~= panel then
        return false
    end

    return true
end

-- the two faces of the icon at this sidebar size.
local function QSF_icons(textureWidth)
    local stem = "media/ui/Sidebar/" .. textureWidth .. "/Quests_"
    return getTexture(stem .. "Off_" .. textureWidth .. ".png"), getTexture(stem .. "On_" .. textureWidth .. ".png")
end

-- where the flyout cell goes, and whether what it hangs off is out. it is one more cell on
-- the end of the map button's flyout, or beside the map button itself in a sandbox without
-- the minimap, where that button has no flyout.
local function QSF_host(panel, textureWidth)
    local flyout = panel.mapPopup
    if flyout then
        return flyout:getX() + flyout:getWidth(), flyout:getY(), flyout:isVisible()
    end

    local button = panel.mapBtn
    return panel:getAbsoluteX() + button:getX() + textureWidth, panel:getAbsoluteY() + button:getY(),
        button:isMouseOver()
end

-- vanilla's own step from one sidebar button down to the next. its constants are file-local.
local BUTTON_STEP = 15

-- the bottom of the lowest sidebar button that is showing, ours aside.
local function QSF_lowestButton(panel)
    local bottom = 0

    for _, child in pairs(panel:getChildren()) do
        if child ~= panel.QSF_button and child.Type == "ISButton" and child:isVisible() then
            bottom = math.max(bottom, child:getBottom())
        end
    end

    return bottom
end

local function QSF_onButton(panel)
    QSF.togglePanel(panel.chr)
end

-- a sandbox with the map switched off has no map button to hang the icon off. there it is
-- a sidebar button of its own, under the rest, built the way vanilla builds those.
local function QSF_ensureButton(panel, textureWidth)
    local button = panel.QSF_button

    if not button then
        button = ISButton:new(0, 0, textureWidth, textureWidth * 0.75, "", panel, QSF_onButton)
        button.iconOff, button.iconOn = QSF_icons(textureWidth)
        button:setImage(button.iconOff)
        button:initialise()
        button:instantiate()
        button:setDisplayBackground(false)
        button:ignoreWidthChange()
        button:ignoreHeightChange()

        panel:addChild(button)
        panel:addMouseOverToolTipItem(button, getText("IGUI_QSF_PanelTooltip"))
        panel.QSF_button = button
    end

    -- vanilla shows and hides its last few buttons from one frame to the next, the admin
    -- one for one, so under the rest is not a place that stays put.
    local y = QSF_lowestButton(panel) + BUTTON_STEP
    if button:getY() ~= y then
        button:setY(y)
        panel:shrinkWrap()
    end

    button:setImage(QSF.isWindowOpen(panel.playerNum) and button.iconOn or button.iconOff)
    button:setVisible("Tutorial" ~= getCore():getGameMode())
end

QSF_Popup = ISPanel:derive("QSF_Popup")

function QSF_Popup:new(x, y, width, height, chr)
    local o = ISPanel:new(x, y, width, height)
    setmetatable(o, self)
    self.__index = self

    o.chr = chr
    o.playerNum = chr:getPlayerNum()
    o.backgroundColor = { r = 0, g = 0, b = 0, a = 0 }
    o.borderColor = { r = 0, g = 0, b = 0, a = 0 }

    return o
end

function QSF_Popup:setTextures(textureWidth)
    if self.textureWidth == textureWidth then return end

    self.textureWidth = textureWidth
    self.iconOff, self.iconOn = QSF_icons(textureWidth)
end

function QSF_Popup:render()
    local texture = self.iconOff
    if QSF.isWindowOpen(self.playerNum) then
        texture = self.iconOn or texture
    end

    -- a missing texture should cost us our icon, not the whole sidebar render pass.
    if texture then
        self:drawTexture(texture, 0, 0, 1, 1, 1, 1)
    end
end

function QSF_Popup:onMouseMove(dx, dy)
    self:showTooltip(getText("IGUI_QSF_PanelTooltip"))
    return true
end

function QSF_Popup:onMouseMoveOutside(dx, dy)
    self:hideTooltip()
    return true
end

function QSF_Popup:onMouseDown(x, y)
    self:hideTooltip()

    QSF.togglePanel(self.chr)

    return true
end

function QSF_Popup:showTooltip(text)
    if not text then return end

    if not self.tooltip then
        self.tooltip = ISToolTip:new()
        self.tooltip:initialise()
        self.tooltip:instantiate()
        self.tooltip:setOwner(self)
    end

    self.tooltip:setName(text)
    self.tooltip:setVisible(true)
    self.tooltip:addToUIManager()
    self.tooltip:bringToTop()
end

function QSF_Popup:hideTooltip()
    if self.tooltip and self.tooltip:isVisible() then
        self.tooltip:removeFromUIManager()
        self.tooltip:setVisible(false)
    end
end

-- makes the icon if there is none and puts it in its place: a cell that flies out with the
-- map button's, or a button of the sidebar's own where there is no map button. true when
-- the cell should be out.
local function QSF_ensureIcon(panel)
    if not panel or not panel.chr or panel.chr:getPlayerNum() ~= 0 or not panel.craftingBtn then
        return false
    end
    if not QSF_isCurrentPanel(panel) then return false end

    local textureWidth = QSF_textureWidth()
    local textureHeight = textureWidth * 0.75

    if not panel.mapBtn then
        QSF_ensureButton(panel, textureWidth)
        return false
    end

    if not panel.QSF_popup then
        panel.QSF_popup = QSF_Popup:new(0, 0, textureWidth, textureHeight, panel.chr)
        panel.QSF_popup.owner = panel
        panel.QSF_popup:addToUIManager()
        panel.QSF_popup:setVisible(false)
    end

    local x, y, hostOut = QSF_host(panel, textureWidth)
    panel.QSF_popup:setX(x)
    panel.QSF_popup:setY(y)
    panel.QSF_popup:setWidth(textureWidth)
    panel.QSF_popup:setHeight(textureHeight)
    panel.QSF_popup:setTextures(textureWidth)

    return hostOut
end

local function QSF_updateVisibility(panel, hostOut)
    if not panel or not panel.QSF_popup then return end

    local show = hostOut or panel.QSF_popup:isMouseOver()

    panel.QSF_popup:setVisible(show)

    if show then
        panel.QSF_popup:bringToTop()
    else
        panel.QSF_popup:hideTooltip()
    end
end

local function QSF_patchSidebar()
    if not ISEquippedItem then
        require "ISUI/ISEquippedItem"
    end
    if not ISEquippedItem or ISEquippedItem.QSF_PatchApplied then return end

    ISEquippedItem.QSF_PatchApplied = true
    local originalInitialise = ISEquippedItem.initialise
    local originalPrerender = ISEquippedItem.prerender
    local originalRemove = ISEquippedItem.removeFromUIManager
    local originalCheckSize = ISEquippedItem.checkSidebarSizeOption

    function ISEquippedItem:initialise()
        if originalInitialise then originalInitialise(self) end
        QSF_ensureIcon(self)
    end

    function ISEquippedItem:prerender()
        if originalPrerender then originalPrerender(self) end
        if not QSF_isCurrentPanel(self) then return end

        QSF_updateVisibility(self, QSF_ensureIcon(self))
    end

    function ISEquippedItem:removeFromUIManager()
        if self.QSF_popup then
            self.QSF_popup:hideTooltip()
            self.QSF_popup:removeFromUIManager()
            self.QSF_popup = nil
        end

        if originalRemove then
            originalRemove(self)
        else
            ISPanel.removeFromUIManager(self)
        end
    end

    function ISEquippedItem:checkSidebarSizeOption()
        if originalCheckSize then originalCheckSize(self) end
        if QSF_isCurrentPanel(self) then QSF_ensureIcon(self) end
    end
end

-- wrapping the sidebar while the UI is still booting can leave it half-built.
Events.OnGameStart.Add(QSF_patchSidebar)
