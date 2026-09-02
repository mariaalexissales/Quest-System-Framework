----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Json"
require "QSF_Schema"

if not QSF.isAuthority() then return end

QSF = QSF or {}
QSF_Defs = QSF_Defs or {}

QSF_Defs.all = QSF_Defs.all or {}
QSF_Defs.ordered = QSF_Defs.ordered or {}
QSF_Defs.loaded = false

-- if the listing gives us nothing, this name always works.
local FALLBACK = "quests.json"

function QSF_Defs.listFiles()
    local files = {}

    local ok, listing = pcall(function() return listFilesInZomboidLuaDirectory(QSF.DIR) end)
    if ok and listing then
        for i = 0, listing:size() - 1 do
            local entry = tostring(listing:get(i))
            if entry:lower():match("%.json$") then
                -- the listing hands back either a bare name or a path.
                if entry:find("[/\\]") then
                    files[#files + 1] = entry
                else
                    files[#files + 1] = QSF.DIR .. "/" .. entry
                end
            end
        end
    end

    if #files == 0 then
        local path = QSF.DIR .. "/" .. FALLBACK
        if fileExists(path) then files[1] = path end
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

-- admins write both a bare array and an object with a quests key.
local function QSF_questList(decoded)
    if type(decoded) ~= "table" then return nil end
    if decoded.quests ~= nil then
        if type(decoded.quests) ~= "table" then return nil end
        return decoded.quests
    end
    return decoded
end

function QSF_Defs.load()
    local defs = {}
    local sources = {}
    local files = QSF_Defs.listFiles()
    local loadedCount, rejected, warnings = 0, 0, 0

    for _, path in ipairs(files) do
        local text, readErr = QSF_Defs.readFile(path)

        if not text then
            QSF.warn(path .. ": " .. readErr)
            rejected = rejected + 1
        else
            local decoded, jsonErr = QSF_Json.decode(text)

            if not decoded then
                QSF.warn(path .. ": " .. tostring(jsonErr))
                rejected = rejected + 1
            else
                local list = QSF_questList(decoded)

                if not list then
                    QSF.warn(path .. ": expected a list of quests, or an object with a quests list")
                    rejected = rejected + 1
                else
                    for _, raw in ipairs(list) do
                        local def, errors = QSF_Schema.normalise(raw, path)

                        for _, message in ipairs(errors or {}) do
                            QSF.warn(message)
                            warnings = warnings + 1
                        end

                        if def then
                            if defs[def.key] then
                                QSF.warn(def.key .. ": already defined in " .. tostring(sources[def.key])
                                    .. ", the copy in " .. path .. " wins")
                            end
                            defs[def.key] = def
                            sources[def.key] = path
                            loadedCount = loadedCount + 1
                        else
                            rejected = rejected + 1
                        end
                    end
                end
            end
        end
    end

    for _, message in ipairs(QSF_Schema.crossValidate(defs)) do
        QSF.warn(message)
        warnings = warnings + 1
    end

    QSF_Defs.all = defs
    QSF_Defs.ordered = QSF_Defs.sort(defs)
    QSF_Defs.loaded = true

    QSF.log(#files .. " files, " .. loadedCount .. " quests loaded, "
        .. rejected .. " rejected, " .. warnings .. " warnings")

    if #files == 0 then
        QSF.log("no quest files found. drop .json files into Zomboid/Lua/" .. QSF.DIR .. "/")
    end

    return defs
end

-- pairs() alone would reshuffle the list between openings.
function QSF_Defs.sort(defs)
    local ordered = {}
    for _, def in pairs(defs) do ordered[#ordered + 1] = def end

    table.sort(ordered, function(a, b)
        if a.order ~= b.order then return a.order < b.order end
        return a.key < b.key
    end)

    return ordered
end

function QSF_Defs.get(key)
    return QSF_Defs.all[key]
end

Events.OnInitGlobalModData.Add(function()
    QSF_Defs.load()
end)
