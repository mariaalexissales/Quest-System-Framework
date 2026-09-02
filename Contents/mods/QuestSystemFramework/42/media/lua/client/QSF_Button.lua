----------
--ESTRAL--
----------

require "ISUI/ISButton"
require "QSF_Theme"

QSF_Button = ISButton:derive("QSF_Button")

function QSF_Button:new(x, y, width, height, title, target, onclick)
    local o = ISButton:new(x, y, width, height, title, target, onclick)
    setmetatable(o, self)
    self.__index = self

    o.font = UIFont.Small
    o.selected = false

    -- the vanilla rect-and-border chrome would sit under the NeatUI art.
    o.displayBackground = false

    return o
end

function QSF_Button:sizeToTitle(padding)
    self:setWidth(getTextManager():MeasureStringX(self.font, self.title) + (padding or 20))
    return self
end

function QSF_Button:state()
    if not self.enable then return QSF_Theme.STATES.disabled end
    if self.pressed then return QSF_Theme.STATES.pressed end
    if self.selected then return QSF_Theme.STATES.selected end
    if self.mouseOver and self:isMouseOver() then return QSF_Theme.STATES.hover end
    return QSF_Theme.STATES.normal
end

function QSF_Button:prerender()
    ISButton.prerender(self)

    local state = self:state()
    self.textColor = self.textColor or {}
    self.textColor.r, self.textColor.g, self.textColor.b = state.text[1], state.text[2], state.text[3]
    self.textColor.a = 1

    if state.fill then
        self:drawRect(0, 0, self.width, self.height, state.fill[4], state.fill[1], state.fill[2], state.fill[3])
    end

    local textures = QSF_Theme.textures()
    if NeatTool and NeatTool.ThreePatch then
        NeatTool.ThreePatch.drawHorizontal(self, 0, 0, self.width, self.height,
            textures.left, textures.middle, textures.right,
            state.alpha, state.cap[1], state.cap[2], state.cap[3])
    end
end
