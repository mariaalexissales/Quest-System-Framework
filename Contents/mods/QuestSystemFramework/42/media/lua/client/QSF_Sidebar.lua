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

-- only for a sandbox with the map switched off, where the icon is back beside the crafting
-- button. cell 0 is that button and anything flying out of it claims the cells after,
-- measured every frame so load order does not matter. Bundle Up! is named outright because
-- it measures the crafting popup exactly the way this does and would otherwise land on the
-- same cell.
local function QSF_cellOffset(panel, textureWidth)
    local cells = 1

    if panel.craftingPopup and panel.craftingPopup.getWidth then
        local width = panel.craftingPopup:getWidth() or 0
        cells = math.max(cells, math.ceil(width / textureWidth))
    end

    if panel.BUUI_popup then
        cells = cells + 1
    end

    return cells
end

-- the cursor on the crafting button or on anything else flying out of it. travelling right
-- from the button to our cell crosses those, and without them it loses us halfway.
local function QSF_overCrafting(panel)
    if panel.craftingBtn:isMouseOver() then return true end

    if panel.craftingPopup and panel.craftingPopup.isMouseOver and panel.craftingPopup:isMouseOver() then
        return true
    end

    return panel.BUUI_popup ~= nil and panel.BUUI_popup.isMouseOver ~= nil and panel.BUUI_popup:isMouseOver()
end

-- where the icon goes, and whether what it hangs off is out. it is one more cell on the end
-- of the map button's flyout. a sandbox without the minimap has no flyout and one without
-- the map has no map button, and then it sits beside whichever button is left.
local function QSF_host(panel, textureWidth)
    local flyout = panel.mapPopup
    if flyout then
        return flyout:getX() + flyout:getWidth(), flyout:getY(), flyout:isVisible()
    end

    local left, top = panel:getAbsoluteX(), panel:getAbsoluteY()

    local button = panel.mapBtn
    if button then
        return left + button:getX() + textureWidth, top + button:getY(), button:isMouseOver()
    end

    button = panel.craftingBtn
    return left + button:getX() + QSF_cellOffset(panel, textureWidth) * textureWidth, top + button:getY(),
        QSF_overCrafting(panel)
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
    self.iconOff = getTexture("media/ui/Sidebar/" .. textureWidth .. "/Quests_Off_" .. textureWidth .. ".png")
    self.iconOn = getTexture("media/ui/Sidebar/" .. textureWidth .. "/Quests_On_" .. textureWidth .. ".png")
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

-- makes the icon if there is none and puts it in its place. true when what it hangs off
-- is out, which is when the icon should be too.
local function QSF_ensurePopup(panel)
    if not panel or not panel.chr or panel.chr:getPlayerNum() ~= 0 or not panel.craftingBtn then
        return false
    end
    if not QSF_isCurrentPanel(panel) then return false end

    local textureWidth = QSF_textureWidth()
    local textureHeight = textureWidth * 0.75

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

    if "Tutorial" == getCore():getGameMode() then
        show = false
    end

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
        QSF_ensurePopup(self)
    end

    function ISEquippedItem:prerender()
        if originalPrerender then originalPrerender(self) end
        if not QSF_isCurrentPanel(self) then return end

        QSF_updateVisibility(self, QSF_ensurePopup(self))
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
        if QSF_isCurrentPanel(self) then QSF_ensurePopup(self) end
    end
end

-- wrapping the sidebar while the UI is still booting can leave it half-built.
Events.OnGameStart.Add(QSF_patchSidebar)
