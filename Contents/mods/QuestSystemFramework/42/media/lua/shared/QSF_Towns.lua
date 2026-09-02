----------
--ESTRAL--
----------

require "QSF_Core"

-- the game names nine regions and getSquareRegion() returns them, but several towns on
-- the map are not regions at all and come back as "General". these are the missing ones.
--
-- centres are the map label positions the game itself draws, lifted from
-- media/maps/Muldraugh, KY/worldmap-annotations.lua, so they sit exactly where the town
-- name appears on the in-game map. the box sizes are a first pass sighted off those
-- positions rather than measured, and want checking against the debug map - an admin who
-- disagrees can always write a raw box in the json instead.

QSF = QSF or {}
QSF_Towns = QSF_Towns or {}

QSF_Towns.DEFS = {
    Ekron       = { cx =   634, cy =  9746, w = 300, h = 300, label = "MapLabel_Ekron",       en = "Ekron" },
    Brandenburg = { cx =  2056, cy =  6070, w = 400, h = 400, label = "MapLabel_Brandenburg", en = "Brandenburg" },
    Irvington   = { cx =  2427, cy = 14185, w = 350, h = 350, label = "MapLabel_Irvington",   en = "Irvington" },
    EchoCreek   = { cx =  3589, cy = 10952, w = 300, h = 300, label = "MapLabel_EchoCreek",   en = "Echo Creek" },
    FallasLake  = { cx =  7253, cy =  8279, w = 300, h = 300, label = "MapLabel_FallasLake",  en = "Fallas Lake" },
}

-- the nine the engine already knows. listed so the ui can name them and so a typo in an
-- admin's json can be answered with "did you mean" rather than silence.
QSF_Towns.VANILLA = {
    Muldraugh     = "MapLabel_Muldraugh",
    WestPoint     = "MapLabel_WestPoint",
    Rosewood      = "MapLabel_Rosewood",
    Riverside     = "MapLabel_Riverside",
    MarchRidge    = "MapLabel_MarchRidge",
    Louisville    = "MapLabel_Louisville",
    ValleyStation = "MapLabel_ValleyStation",
    Jefferson     = nil,
    LAA           = nil,
}

function QSF_Towns.box(name)
    local town = QSF_Towns.DEFS[name]
    if not town then return nil end

    return {
        x = town.cx - town.w / 2,
        y = town.cy - town.h / 2,
        w = town.w,
        h = town.h,
    }
end

function QSF_Towns.displayName(name)
    local town = QSF_Towns.DEFS[name]
    if town then return QSF.text(town.label, town.en) end

    local label = QSF_Towns.VANILLA[name]
    if label then return QSF.text(label, name) end

    return name
end

-- off by default. region zones feed vanilla spawn and metazone logic, so five extra ones
-- can move zombie and loot distribution in ways nobody would ever trace back to a quest
-- mod. the matcher tests our boxes directly instead, which has no side effects at all.
-- turn this on only if you want other mods to see these towns through getSquareRegion().
local function QSF_registerTownZones()
    if not QSF.Config.registerTownZones then return end

    for name, town in pairs(QSF_Towns.DEFS) do
        local box = QSF_Towns.box(name)
        local ok, err = pcall(function()
            getWorld():registerZone(name, "Region", box.x, box.y, 0, box.w, box.h)
        end)
        if not ok then QSF.warn("could not register zone " .. name .. ": " .. tostring(err)) end
        if ok then QSF.log("registered region zone " .. name) end
    end
end

Events.OnLoadMapZones.Add(QSF_registerTownZones)
