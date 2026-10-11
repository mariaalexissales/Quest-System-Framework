----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Json"
require "QSF_Rules"
require "QSF_Schema"

if not QSF.isAuthority() then return end

QSF_Defs = QSF_Defs or {}

QSF_Defs.all = QSF_Defs.all or {}
QSF_Defs.ordered = QSF_Defs.ordered or {}
QSF_Defs.npcs = QSF_Defs.npcs or {}
QSF_Defs.global = QSF_Defs.global or {}
QSF_Defs.globalOrdered = QSF_Defs.globalOrdered or {}
QSF_Defs.loaded = false

-- one more every time the files are read, for anything that keeps something worked out
-- from them.
QSF_Defs.revision = QSF_Defs.revision or 0

-- if the listing gives us nothing, this name always works.
local FALLBACK = "quests.json"

local META_TABLE = "QSF_Meta"

-- ascii only: the file writer's charset is the platform's, so curly quotes can come out mangled.
local STARTER = [[
{
  "quests": [
    {
      "key": "intro_supplies",
      "title": "Something To Build With",
      "description": "You won't last the week with what's in your pockets. <LINE> Bring me the basics and we'll talk about the work that pays.",
      "order": 10,
      "autoComplete": false,
      "objectives": [
        { "type": "collect", "item": "Base.Nails", "count": 10 },
        { "type": "collect", "item": "Base.Plank", "count": 4 }
      ],
      "rewards": {
        "items": [ { "item": "Base.Hammer", "count": 1 } ]
      }
    }
  ]
}
]]

-- the listing hands back a bare name or a path, so only the tail is compared.
local function QSF_isFile(path, name)
    return path:sub(-#name):lower() == name
end

-- the mod's own output, which is nobody's quests.
local function QSF_isOwnFile(path)
    for name in pairs(QSF.OWN_FILES) do
        if QSF_isFile(path, name) then return true end
    end

    return false
end

function QSF_Defs.listFiles()
    local files = {}

    local ok, listing = pcall(function() return listFilesInZomboidLuaDirectory(QSF.DIR) end)
    if ok and listing then
        for i = 0, listing:size() - 1 do
            local entry = tostring(listing:get(i))
            if entry:lower():match("%.json$") and not QSF_isOwnFile(entry) then
                -- the listing hands back either a bare name or a path.
                if entry:find("[/\\]") then
                    files[#files + 1] = entry
                else
                    files[#files + 1] = QSF.DIR .. "/" .. entry
                end
            end
        end
    end

    -- fileExists resolves against the game's media folders, not Zomboid/Lua, so it never sees
    -- this file. reading it through the same resolver the load uses is the reliable check.
    if #files == 0 then
        local path = QSF.DIR .. "/" .. FALLBACK
        if QSF_Defs.readFile(path) then files[1] = path end
    end

    return files
end

-- a missing file is either a nil reader or one whose first line is nil, build depending.
function QSF_Defs.readFile(path)
    local ok, reader = pcall(function() return getFileReader(path, false) end)
    if not ok or not reader then return nil, "could not open" end

    local lines = {}
    local okRead, err = pcall(function()
        local line = reader:readLine()
        while line do
            lines[#lines + 1] = line
            line = reader:readLine()
        end
    end)

    pcall(function() reader:close() end)

    if not okRead then return nil, "read failed: " .. tostring(err) end
    if #lines == 0 then return nil, "empty or missing" end

    return table.concat(lines, "\n")
end

-- nothing else ever writes to Zomboid/Lua, so without this an admin has no folder to find.
-- once per world, or a starter they deleted on purpose would come back every restart.
function QSF_Defs.seed()
    local meta = ModData.getOrCreate(META_TABLE)
    if meta.seeded then return end
    meta.seeded = true

    if #QSF_Defs.listFiles() > 0 then return end

    local path = QSF.DIR .. "/" .. FALLBACK

    -- there but unreadable is still somebody's file.
    local _, readErr = QSF_Defs.readFile(path)
    if readErr and readErr:find("^read failed") then return end

    if QSF_Defs.writeFile(FALLBACK, STARTER) then
        QSF.log("created Zomboid/Lua/" .. path .. " with a starter quest")
    end
end

-- one of the lists a file can hold under a key of its own, or nil.
local function QSF_listOf(decoded, field)
    if type(decoded) ~= "table" or type(decoded[field]) ~= "table" then return nil end
    return decoded[field]
end

-- admins write both a bare array and an object with a quests key. npcs and global quests
-- ride along in the same files under theirs, and a bare array has nowhere to put them.
local function QSF_questList(decoded)
    if type(decoded) ~= "table" then return nil end
    if decoded.quests ~= nil then return QSF_listOf(decoded, "quests") end
    return decoded
end

-- what tells the three lists apart: who reads an entry, what it is called in the log, and
-- what it is counted under. their keys are kept apart too, so one of each can share a name.
local KINDS = {
    npcs = {
        normalise = QSF_Schema.normaliseNpc, label = "npc ", count = "npcs",
        -- only these can be taken away again from inside the game.
        file = function(npc, path) npc.placed = QSF_isFile(path, QSF.NPC_FILE) end,
    },
    global = { normalise = QSF_Schema.normaliseGlobal, label = "global ", count = "globals" },
    quests = { normalise = QSF_Schema.normalise, label = "", count = "quests" },
}

-- one file, decoded, or nil with the file counted as rejected and the reason logged.
local function QSF_readJson(path, tally)
    local text, readErr = QSF_Defs.readFile(path)
    if not text then
        QSF.warn(path .. ": " .. readErr)
        tally.rejected = tally.rejected + 1
        return nil
    end

    local decoded, jsonErr = QSF_Json.decode(text)
    if not decoded then
        QSF.warn(path .. ": " .. tostring(jsonErr))
        tally.rejected = tally.rejected + 1
        return nil
    end

    return decoded
end

local function QSF_warnAll(errors, tally)
    for _, message in ipairs(errors or {}) do
        QSF.warn(message)
        tally.warnings = tally.warnings + 1
    end
end

-- into is key to entry, and sources is key to the file it came from, for naming both
-- files when a key turns up twice. the later copy wins and is only counted the once.
local function QSF_addAll(list, kind, path, into, sources, tally)
    for _, raw in ipairs(list or {}) do
        local entry, errors = kind.normalise(raw, path)
        QSF_warnAll(errors, tally)

        if not entry then
            tally.rejected = tally.rejected + 1
        else
            if into[entry.key] then
                QSF.warn(kind.label .. entry.key .. ": already defined in " .. tostring(sources[entry.key])
                    .. ", the copy in " .. path .. " wins")
            else
                tally[kind.count] = tally[kind.count] + 1
            end

            if kind.file then kind.file(entry, path) end
            into[entry.key] = entry
            sources[entry.key] = path
        end
    end
end

function QSF_Defs.load()
    local found, sources = {}, {}
    for name in pairs(KINDS) do found[name], sources[name] = {}, {} end

    local files = QSF_Defs.listFiles()
    local tally = { quests = 0, npcs = 0, globals = 0, rejected = 0, warnings = 0 }

    for _, path in ipairs(files) do
        local decoded = QSF_readJson(path, tally)
        if decoded then
            for _, name in ipairs({ "npcs", "global" }) do
                QSF_addAll(QSF_listOf(decoded, name), KINDS[name], path, found[name], sources[name], tally)
            end

            local quests = QSF_questList(decoded)
            if quests then
                QSF_addAll(quests, KINDS.quests, path, found.quests, sources.quests, tally)
            else
                QSF.warn(path .. ": expected a list of quests, or an object with a quests list")
                tally.rejected = tally.rejected + 1
            end
        end
    end

    local defs, npcs, globals = found.quests, found.npcs, found.global

    QSF_warnAll(QSF_Schema.crossValidate(defs, npcs, globals), tally)

    QSF_Defs.all = defs
    QSF_Defs.ordered = QSF_Rules.sorted(defs)
    QSF_Defs.npcs = npcs
    QSF_Defs.global = globals
    QSF_Defs.globalOrdered = QSF_Rules.sorted(globals)
    QSF_Defs.loaded = true
    QSF_Defs.revision = QSF_Defs.revision + 1

    QSF.log(#files .. " files, " .. tally.quests .. " quests loaded, "
        .. tally.rejected .. " rejected, " .. tally.warnings .. " warnings")

    -- its own line, and only when there are any, so the summary above reads the way it
    -- always has on a server that never uses them.
    if tally.npcs > 0 then QSF.log(tally.npcs .. " npcs loaded") end
    if tally.globals > 0 then QSF.log(tally.globals .. " global quests loaded") end

    if #files == 0 then
        QSF.log("no quest files found. drop .json files into Zomboid/Lua/" .. QSF.DIR .. "/")
    end

    return defs
end

function QSF_Defs.get(key)
    return QSF_Defs.all[key]
end

function QSF_Defs.npc(key)
    return key and QSF_Defs.npcs[key] or nil
end

-- the order they are written in, which is the order somebody reading the file wants.
QSF_Defs.NPC_FIELDS = { "key", "name", "x", "y", "z", "outfit", "female", "skin", "facing", "greeting" }

local PLACED_HEADER = "// written by the game whenever an admin places or removes an npc.\n"
    .. "// edits made here are kept. an entry the game cannot read is dropped the next time it writes.\n"

-- every npc, or only the ones the game placed itself. sorted, so the file does not
-- reshuffle between writes and every client is handed the list in the same order.
function QSF_Defs.npcList(placedOnly)
    local list = {}

    for _, npc in pairs(QSF_Defs.npcs) do
        if npc.placed or not placedOnly then list[#list + 1] = npc end
    end

    table.sort(list, function(a, b) return a.key < b.key end)

    return list
end

-- one of the mod's own files in the quest folder, replaced whole. false if it could not be.
function QSF_Defs.writeFile(name, text)
    local path = QSF.DIR .. "/" .. name

    local ok, err = pcall(function()
        local writer = getFileWriter(path, true, false)
        writer:write(text)
        writer:close()
    end)

    if not ok then
        QSF.warn("could not write Zomboid/Lua/" .. path .. ": " .. tostring(err))
        return false
    end

    return true
end

-- the whole file, every time. it is the one file in the folder nobody wrote by hand, so
-- there are no comments or layout of anybody's to lose.
function QSF_Defs.writePlaced(list)
    local entries = {}

    for index, npc in ipairs(list) do
        local entry = {}
        for _, field in ipairs(QSF_Defs.NPC_FIELDS) do entry[field] = npc[field] end
        entries[index] = entry
    end

    return QSF_Defs.writeFile(QSF.NPC_FILE,
        PLACED_HEADER .. QSF_Json.encode({ npcs = entries }, QSF_Defs.NPC_FIELDS) .. "\n")
end

-- Reload goes straight to load(), so only a server start can seed.
Events.OnInitGlobalModData.Add(function()
    QSF_Defs.seed()
    QSF_Defs.load()
end)
