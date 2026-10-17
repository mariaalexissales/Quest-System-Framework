----------
--ESTRAL--
----------

require "ISUI/Maps/ISWorldMap"
require "ISUI/Maps/ISMiniMap"
require "QSF_Core"
require "QSF_Theme"
require "QSF_ClientState"
require "QSF_NpcClient"

-- the giver of every quest the player has taken, on the world map and the minimap, in the
-- same "?" the marker over their head is. what is only on offer is the overhead marker's
-- business: the map is for finding the way back.
QSF_MapMarker = QSF_MapMarker or {}

-- pixels. the map's own symbols keep a size of their own too, whatever the zoom.
local WORLD_SIZE = 24
local MINI_SIZE = 16

-- canAccept moves with the clock, skills and kill count, none of which bump a revision.
local RECOUNT_MS = 1000

-- the hover box: its padding, and how far it sits from the cursor.
local PAD = 6
local CURSOR_GAP = 16

local GREY = { r = 0.62, g = 0.62, b = 0.62 }

local LOOKS = {
    turnin = QSF_Theme.COL_ACTIVE,
    progress = GREY,
}

local TEXTURE = nil

-- per player, since a split screen has a map each.
local caches = {}

local function QSF_texture()
    if TEXTURE == nil then TEXTURE = getTexture("media/ui/QSF/Marker_TurnIn.png") end
    return TEXTURE
end

function QSF_MapMarker.entries(playerNum)
    local player = getSpecificPlayer(playerNum)
    if not player then return {} end

    local cache = caches[playerNum]
    local now = getTimestampMs()
    if cache and cache.revision == QSF_ClientState.revision and now - cache.at < RECOUNT_MS then
        return cache.entries
    end

    local entries = {}
    for key, npc in pairs(QSF_ClientState.npcs) do
        local look, defs = QSF_NpcClient.accepted(key, player)
        if look then entries[#entries + 1] = { npc = npc, look = look, defs = defs } end
    end

    caches[playerNum] = { revision = QSF_ClientState.revision, at = now, entries = entries }
    return entries
end

local function QSF_drawHover(element, entry)
    local tm = getTextManager()
    local font = UIFont.Small
    local lineH = tm:getFontHeight(font)

    local lines = { entry.npc.name }
    for _, def in ipairs(entry.defs) do lines[#lines + 1] = def.title end

    local width = 0
    for _, line in ipairs(lines) do width = math.max(width, tm:MeasureStringX(font, line)) end
    width = width + PAD * 2
    local height = #lines * lineH + PAD * 2

    -- beside the cursor, and back onto the map when that would run off it.
    local x = element:getMouseX() + CURSOR_GAP
    local y = element:getMouseY() + CURSOR_GAP
    if x + width > element.width then x = element:getMouseX() - CURSOR_GAP - width end
    if y + height > element.height then y = element:getMouseY() - CURSOR_GAP - height end

    element:drawRect(x, y, width, height, 0.85, 0.08, 0.08, 0.08)
    element:drawRectBorder(x, y, width, height, 0.5, 1, 1, 1)

    for i, line in ipairs(lines) do
        local colour = i == 1 and QSF_Theme.COL_TITLE or QSF_Theme.COL_TEXT
        element:drawText(line, x + PAD, y + PAD + (i - 1) * lineH, colour.r, colour.g, colour.b, 1, font)
    end
end

-- element is the map's own ui, with the mapAPI that knows where a tile is on it.
function QSF_MapMarker.draw(element, size, hover)
    if not element.mapAPI then return end

    local entries = QSF_MapMarker.entries(element.playerNum or 0)
    if #entries == 0 then return end

    local texture = QSF_texture()
    local mouseX, mouseY = nil, nil
    if hover then mouseX, mouseY = element:getMouseX(), element:getMouseY() end

    local hovered = nil

    for _, entry in ipairs(entries) do
        local wx, wy = entry.npc.x + 0.5, entry.npc.y + 0.5
        local px = element.mapAPI:worldToUIX(wx, wy)
        local py = element.mapAPI:worldToUIY(wx, wy)

        -- standing on the point, the way a pin does.
        local x, y = px - size / 2, py - size

        -- the minimap draws nothing outside itself, and neither should this, not even half
        -- an icon over its border.
        if x >= 0 and y >= 0 and x + size <= element.width and py <= element.height then
            local colour = LOOKS[entry.look]

            element:drawTextureScaled(texture, x, y, size, size, 1, colour.r, colour.g, colour.b)

            if hover and mouseX >= x and mouseX <= x + size and mouseY >= y and mouseY <= y + size then
                hovered = entry
            end
        end
    end

    -- after every marker, so no marker is drawn over the box.
    if hovered then QSF_drawHover(element, hovered) end
end

local function QSF_patch()
    if ISWorldMap and not ISWorldMap.QSF_PatchApplied then
        ISWorldMap.QSF_PatchApplied = true
        local originalRender = ISWorldMap.render

        function ISWorldMap:render()
            originalRender(self)
            QSF_MapMarker.draw(self, WORLD_SIZE, true)
        end
    end

    if ISMiniMapInner and not ISMiniMapInner.QSF_PatchApplied then
        ISMiniMapInner.QSF_PatchApplied = true
        local originalRender = ISMiniMapInner.render

        function ISMiniMapInner:render()
            originalRender(self)
            QSF_MapMarker.draw(self, MINI_SIZE, false)
        end
    end
end

QSF_patch()
