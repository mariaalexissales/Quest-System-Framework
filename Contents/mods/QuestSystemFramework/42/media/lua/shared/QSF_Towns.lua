----------
--ESTRAL--
----------

require "QSF_Core"

QSF = QSF or {}
QSF_Towns = QSF_Towns or {}

-- the towns getSquareRegion() answers "General" for. centres are the map label positions
-- from media/maps/Muldraugh, KY/worldmap-annotations.lua, so a box sits where the name is
-- drawn on the in-game map. the sizes are sighted off those positions, not measured.
QSF_Towns.DEFS = {
    Ekron       = { cx =   634, cy =  9746, w = 300, h = 300, label = "MapLabel_Ekron",       en = "Ekron" },
    Brandenburg = { cx =  2056, cy =  6070, w = 400, h = 400, label = "MapLabel_Brandenburg", en = "Brandenburg" },
    Irvington   = { cx =  2427, cy = 14185, w = 350, h = 350, label = "MapLabel_Irvington",   en = "Irvington" },
    EchoCreek   = { cx =  3589, cy = 10952, w = 300, h = 300, label = "MapLabel_EchoCreek",   en = "Echo Creek" },
    FallasLake  = { cx =  7253, cy =  8279, w = 300, h = 300, label = "MapLabel_FallasLake",  en = "Fallas Lake" },
}

-- Jefferson and LAA have no map label, so they fall through to their raw region name.
QSF_Towns.VANILLA = {
    Muldraugh     = "MapLabel_Muldraugh",
    WestPoint     = "MapLabel_WestPoint",
    Rosewood      = "MapLabel_Rosewood",
    Riverside     = "MapLabel_Riverside",
    MarchRidge    = "MapLabel_MarchRidge",
    Louisville    = "MapLabel_Louisville",
    ValleyStation = "MapLabel_ValleyStation",
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

-- opt-in, and off by default: see the note on QSF.Config.registerTownZones.
local function QSF_registerTownZones()
    if not QSF.Config.registerTownZones then return end

    for name, _ in pairs(QSF_Towns.DEFS) do
        local box = QSF_Towns.box(name)
        getWorld():registerZone(name, "Region", box.x, box.y, 0, box.w, box.h)
        QSF.log("registered region zone " .. name)
    end
end

Events.OnLoadMapZones.Add(QSF_registerTownZones)
