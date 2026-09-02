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

-- cell 0 is the vanilla crafting button; anything already flying out of it claims the
-- cells after. measured every frame rather than assumed, so load order against other
-- sidebar mods does not matter.
--
-- Bundle Up! is called out by name because it is the one mod guaranteed to be sitting in
-- the cell we would otherwise take, and both are mine. anything else that measures the
-- crafting popup the same way will still land on us, which is the general problem with
-- this sidebar and not something a single mod can fix.
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

    if QSF.isWindowOpen(self.playerNum) then
        QSF.getWindow(self.playerNum):onCloseClick()
    else
        QSF.openPanel(self.chr)
    end

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

local function QSF_ensurePopup(panel)
    if not panel or not panel.chr or panel.chr:getPlayerNum() ~= 0 or not panel.craftingBtn then
        return
    end
    if not QSF_isCurrentPanel(panel) then return end

    local textureWidth = QSF_textureWidth()
    local textureHeight = textureWidth * 0.75

    if not panel.QSF_popup then
        panel.QSF_popup = QSF_Popup:new(0, 0, textureWidth, textureHeight, panel.chr)
        panel.QSF_popup.owner = panel
        panel.QSF_popup:addToUIManager()
        panel.QSF_popup:setVisible(false)
    end

    local offset = QSF_cellOffset(panel, textureWidth)
    panel.QSF_popup:setX(panel:getAbsoluteX() + panel.craftingBtn:getX() + offset * textureWidth)
    panel.QSF_popup:setY(panel:getAbsoluteY() + panel.craftingBtn:getY())
    panel.QSF_popup:setWidth(textureWidth)
    panel.QSF_popup:setHeight(textureHeight)
    panel.QSF_popup:setTextures(textureWidth)
end

local function QSF_updateVisibility(panel)
    if not panel or not panel.craftingBtn or not panel.QSF_popup then return end
    if not QSF_isCurrentPanel(panel) then return end

    local show = panel.craftingBtn:isMouseOver()
        or panel.QSF_popup:isMouseOver()
        or QSF.isWindowOpen(panel.chr:getPlayerNum())

    -- without this the cursor loses us halfway: travelling right from the crafting
    -- button to our cell crosses whatever else is flying out in between.
    if not show and panel.craftingPopup and panel.craftingPopup.isMouseOver then
        show = panel.craftingPopup:isMouseOver()
    end

    if not show and panel.BUUI_popup and panel.BUUI_popup.isMouseOver then
        show = panel.BUUI_popup:isMouseOver()
    end

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

        QSF_ensurePopup(self)
        QSF_updateVisibility(self)
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
