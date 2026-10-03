----------
--ESTRAL--
----------

require "ISUI/ISPanel"
require "QSF_Core"
require "QSF_Rules"
require "QSF_Theme"
require "QSF_ClientState"
require "QSF_NpcClient"

-- one element draws every marker. it has no size of its own and never takes the mouse;
-- the foraging eye is built the same way and sits over the player's head the same way.
QSF_NpcMarker = ISPanel:derive("QSF_NpcMarker")

-- tiles. past this the npc is off most screens anyway.
local RANGE = 30

-- pixels at the closest zoom. the icon shrinks as the camera pulls out, down to a floor
-- that is still readable.
local SIZE = 40
local MIN_SIZE = 18

-- how far above the feet the top of a head is, in screen pixels at the closest zoom.
local HEAD = 150

-- canAccept moves with the clock, skills and kill count, none of which bump a revision.
local RECOUNT_MS = 1000

local GREY = { r = 0.62, g = 0.62, b = 0.62 }

local LOOKS = {
    available = { texture = "quest", colour = QSF_Theme.COL_ACTIVE },
    turnin = { texture = "turnIn", colour = QSF_Theme.COL_ACTIVE },
    progress = { texture = "turnIn", colour = GREY },
}

local TEXTURES = nil

local function QSF_textures()
    if TEXTURES == nil then
        TEXTURES = {
            quest = getTexture("media/ui/QSF/Marker_Quest.png"),
            turnIn = getTexture("media/ui/QSF/Marker_TurnIn.png"),
        }
    end
    return TEXTURES
end

function QSF_NpcMarker:new(playerNum)
    local o = ISPanel:new(0, 0, 0, 0)
    setmetatable(o, self)
    self.__index = self

    o.playerNum = playerNum
    o.statuses = {}
    o.revision = -1
    o.lastCount = 0

    return o
end

function QSF_NpcMarker:initialise()
    ISPanel.initialise(self)

    -- drawn with the world rather than over the windows, and only in this player's part
    -- of a split screen.
    self:setFollowGameWorld(true)
    self:setRenderThisPlayerOnly(self.playerNum)
end

function QSF_NpcMarker:refresh(player)
    local now = getTimestampMs()
    if self.revision == QSF_ClientState.revision and now - self.lastCount < RECOUNT_MS then return end

    self.revision = QSF_ClientState.revision
    self.lastCount = now

    local statuses = {}
    for key in pairs(QSF_ClientState.npcs) do
        statuses[key] = QSF_NpcClient.status(key, player)
    end
    self.statuses = statuses
end

-- an ISPanel paints a background, and a panel with no size has nothing to paint.
function QSF_NpcMarker:prerender() end

function QSF_NpcMarker:render()
    local player = getSpecificPlayer(self.playerNum)
    if not player or player:isDead() then return end

    self:refresh(player)

    local zoom = getCore():getZoom(self.playerNum)
    local size = math.max(MIN_SIZE, SIZE / zoom)
    local bob = math.sin(getTimestampMs() / 350) * 3

    -- isoToScreen answers in whole-window pixels, and in split screen this player's
    -- share of the window does not start at the corner.
    local left, top = getPlayerScreenLeft(self.playerNum), getPlayerScreenTop(self.playerNum)

    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local textures = QSF_textures()

    for key, status in pairs(self.statuses) do
        local npc = QSF_ClientState.npcs[key]
        local look = LOOKS[status]
        local texture = look and textures[look.texture] or nil

        -- same floor only: a marker hanging in the air over somebody upstairs points at
        -- nothing the player can see.
        if npc and texture and QSF_Rules.isNear(px, py, pz, npc, RANGE) then
            local x, y, z = npc.x + 0.5, npc.y + 0.5, npc.z

            -- over the body when there is one, since that is what the player is looking
            -- at. before it has loaded the tile is the best there is.
            local body = QSF_NpcClient.bodyOf(key)
            if body then x, y, z = body:getX(), body:getY(), body:getZ() end

            local sx = isoToScreenX(self.playerNum, x, y, z) - left - size / 2
            local sy = isoToScreenY(self.playerNum, x, y, z) - top - HEAD / zoom - size + bob

            self:drawTextureScaled(texture, sx, sy, size, size, 1,
                look.colour.r, look.colour.g, look.colour.b)
        end
    end
end

-- OnCreatePlayer fires again for every new character, and one marker layer is plenty.
local function QSF_onCreatePlayer(playerNum)
    if playerNum ~= 0 or QSF_NpcMarker.instance then return end

    local marker = QSF_NpcMarker:new(playerNum)
    marker:initialise()
    marker:addToUIManager()

    QSF_NpcMarker.instance = marker
end

Events.OnCreatePlayer.Add(QSF_onCreatePlayer)
