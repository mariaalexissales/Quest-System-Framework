----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Towns"

QSF = QSF or {}
QSF_Location = QSF_Location or {}

local function QSF_inBox(x, y, box)
    return x >= box.x and x < (box.x + box.w)
       and y >= box.y and y < (box.y + box.h)
end

local function QSF_inCircle(x, y, loc)
    local dx = x - loc.x
    local dy = y - loc.y
    return (dx * dx + dy * dy) <= (loc.radius * loc.radius)
end

-- getZonesAt rather than getSquareRegion: that one needs a square and only answers with
-- Region zones, so a building name could never match.
local function QSF_zoneNames(x, y, z)
    local names, sawRegion = {}, false

    local zones = getWorld():getMetaGrid():getZonesAt(math.floor(x), math.floor(y), math.floor(z or 0))
    if not zones then return names, sawRegion end

    for i = 0, zones:size() - 1 do
        local zone = zones:get(i)
        local name = zone:getName()
        if name and name ~= "" then names[name] = true end
        if zone:getType() == "Region" then sawRegion = true end
    end

    return names, sawRegion
end

-- x, y, z are world tile coordinates. loc is whatever the json gave us, already
-- normalised by QSF_Schema.
function QSF_Location.matchXY(x, y, z, loc)
    if loc == nil or loc == false then return true end
    if not x or not y then return false end

    if type(loc) == "table" then
        if loc.any then
            for _, entry in ipairs(loc.any) do
                if QSF_Location.matchXY(x, y, z, entry) then return true end
            end
            return false
        end

        -- a floor is only checked when the admin asked for one, so a ground-level box
        -- does not silently exclude the second storey of a building.
        if loc.z ~= nil and math.floor(z or 0) ~= math.floor(loc.z) then return false end

        if loc.radius then return QSF_inCircle(x, y, loc) end
        return QSF_inBox(x, y, loc)
    end

    if type(loc) ~= "string" then return false end

    -- our own boxes win over anything the engine knows, so "Ekron" always means what the
    -- admin expects even if another mod registers a zone by that name.
    local box = QSF_Towns.box(loc)
    if box then return QSF_inBox(x, y, box) end

    local names, sawRegion = QSF_zoneNames(x, y, z)
    if names[loc] then return true end

    -- what the engine calls anywhere that is not inside a region.
    if loc == "General" then return not sawRegion end

    return false
end

function QSF_Location.matchSquare(square, loc)
    if loc == nil or loc == false then return true end
    if not square then return false end

    return QSF_Location.matchXY(square:getX(), square:getY(), square:getZ(), loc)
end

function QSF_Location.matchPlayer(player, loc)
    if loc == nil or loc == false then return true end
    if not player then return false end

    return QSF_Location.matchXY(player:getX(), player:getY(), player:getZ(), loc)
end

-- a short human label for the ui. boxes get described by their shape rather than their
-- numbers, which would be noise to a player.
function QSF_Location.describe(loc)
    if loc == nil or loc == false then return nil end

    if type(loc) == "string" then
        return QSF_Towns.displayName(loc)
    end

    if type(loc) == "table" then
        if loc.any then
            local parts = {}
            for _, entry in ipairs(loc.any) do
                local text = QSF_Location.describe(entry)
                if text then parts[#parts + 1] = text end
            end
            if #parts > 0 then return table.concat(parts, " / ") end
        end

        return QSF.text("IGUI_QSF_MarkedArea", "a marked area")
    end

    return nil
end
