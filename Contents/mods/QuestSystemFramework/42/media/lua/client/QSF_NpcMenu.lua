----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_ClientState"
require "QSF_NpcClient"
require "QSF_Dialogue"
require "QSF_NpcPlace"
require "QSF_Theme"
require "ISUI/ISModalDialog"

QSF_NpcMenu = QSF_NpcMenu or {}

-- tiles either way. a character is drawn up the screen from the tile it stands on, so a
-- click on its head lands on the floor a tile or two behind it.
local CLICK = 2

local function QSF_clickedSquare(worldobjects)
    local fetch = ISWorldObjectContextMenu.fetchVars
    if fetch and fetch.clickedSquare then return fetch.clickedSquare end

    local first = worldobjects and worldobjects[1] or nil
    return first and first:getSquare() or nil
end

-- the vanilla menu has no idea a zombie was clicked: its fetch only notices players and
-- animals. the npcs are few and their tiles are known, so the click is matched to those.
function QSF_NpcMenu.npcNear(square)
    local x, y, z = square:getX(), square:getY(), square:getZ()
    local best, bestDist = nil, nil

    for key, npc in pairs(QSF_ClientState.npcs) do
        if npc.z == z then
            local nx, ny = npc.x, npc.y

            local body = QSF_NpcClient.bodyOf(key)
            if body then nx, ny = math.floor(body:getX()), math.floor(body:getY()) end

            local dist = math.max(math.abs(x - nx), math.abs(y - ny))
            if dist <= CLICK and (not bestDist or dist < bestDist) then
                best, bestDist = npc, dist
            end
        end
    end

    return best
end

-- reach is tested again on arrival: the walk can be cut short, and the npc can have
-- been moved by a reload while the player was on the way.
function QSF_NpcMenu.onArrive(player, npcKey)
    local npc = QSF_ClientState.npcs[npcKey]
    if npc and QSF_Rules.inReach(player, npc) then
        QSF_Dialogue.open(player, npcKey)
    end
end

function QSF_NpcMenu.onTalk(playerNum, npcKey)
    local player = getSpecificPlayer(playerNum)
    local npc = QSF_ClientState.npcs[npcKey]
    if not player or not npc then return end

    if QSF_Rules.inReach(player, npc) then
        QSF_Dialogue.open(player, npcKey)
        return
    end

    local square = getCell():getGridSquare(npc.x, npc.y, npc.z)
    local adjacent = square and AdjacentFreeTileFinder.Find(square, player) or nil
    if not adjacent then return end

    ISTimedActionQueue.clear(player)

    local walk = ISWalkToTimedAction:new(player, adjacent)
    walk:setOnComplete(QSF_NpcMenu.onArrive, player, npcKey)
    ISTimedActionQueue.add(walk)
end

-- on a server this is the admins. in singleplayer everybody is the admin of their own
-- world, and an extra line on every right-click of every tile would be in the way of all
-- the people who never place anyone. debug mode is how a singleplayer world says it is
-- being worked on.
local function QSF_canPlace(player)
    if QSF.hasRemoteServer() then return QSF.isAdmin(player) end
    return getDebug()
end

function QSF_NpcMenu.onPlace(playerNum, x, y, z)
    QSF_NpcPlace.show(playerNum, x, y, z)
end

-- asked first: the quests this npc gave drop back into the log for everybody, which is
-- not something to do with a slip of the mouse.
function QSF_NpcMenu.onRemove(playerNum, npcKey)
    local npc = QSF_ClientState.npcs[npcKey]
    if not npc then return end

    QSF_Theme.confirm(getText("IGUI_QSF_RemoveNpcConfirm", npc.name), nil,
        QSF_NpcMenu.onConfirmRemove, playerNum, npcKey)
end

function QSF_NpcMenu.onConfirmRemove(_, button, npcKey)
    if button.internal ~= "YES" or not npcKey then return end
    QSF_Net.toServer("npcRemove", { key = npcKey })
end

-- the Pre event, because the plain one is skipped inside a safehouse the player has no
-- rights in, and an npc stood in somebody's base should still talk.
local function QSF_onPreFill(playerNum, context, worldobjects, test)
    if playerNum ~= 0 then return end

    local square = QSF_clickedSquare(worldobjects)
    if not square then return end

    local npc = QSF_NpcMenu.npcNear(square)
    local canPlace = QSF_canPlace(getSpecificPlayer(playerNum))

    if not npc and not canPlace then return end

    -- a controller probing for whether there is anything to do here.
    if test then return ISWorldObjectContextMenu.setTest() end

    if npc then
        context:addOption(getText("IGUI_QSF_TalkTo", npc.name), playerNum, QSF_NpcMenu.onTalk, npc.key)
    end

    if not canPlace then return end

    if not npc then
        context:addOption(getText("IGUI_QSF_PlaceNpc"), playerNum, QSF_NpcMenu.onPlace,
            square:getX(), square:getY(), square:getZ())
    elseif npc.placed then
        -- one written into a file by hand is taken out of that file by hand.
        context:addOption(getText("IGUI_QSF_RemoveNpc", npc.name), playerNum, QSF_NpcMenu.onRemove, npc.key)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(QSF_onPreFill)
