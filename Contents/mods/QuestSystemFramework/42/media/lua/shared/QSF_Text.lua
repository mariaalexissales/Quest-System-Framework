----------
--ESTRAL--
----------

require "QSF_Core"

QSF_Text = QSF_Text or {}

-- what a greeting, a line of dialogue or a description can ask for by name. braces, because
-- angle brackets already belong to <LINE> and <RGB:>.
local KNOWN = { player = true, npc = true, quest = true }
local PATTERN = "{(%a+)}"

-- values is name to text. a name with nothing to put in comes back exactly as it was
-- written, which is more use to whoever wrote it than a hole in the sentence.
function QSF_Text.fill(text, values)
    if type(text) ~= "string" or not text:find("{", 1, true) then return text end

    local filled = text:gsub(PATTERN, function(name)
        local value = values and values[name:lower()]
        if value == nil or value == "" then return "{" .. name .. "}" end
        return tostring(value)
    end)

    return filled
end

-- who is being spoken to, who is speaking, and the quest in question. any of them can be
-- missing: a greeting has no quest, and a quest in the log may have no npc.
function QSF_Text.values(player, npc, def)
    local descriptor = player and player:getDescriptor() or nil

    return {
        player = descriptor and descriptor:getForename() or nil,
        npc = npc and npc.name or nil,
        quest = def and def.title or nil,
    }
end

-- the names in a text that are none of the above, each once, in the order they appear.
function QSF_Text.unknown(text)
    local out, seen = {}, {}
    if type(text) ~= "string" then return out end

    for name in text:gmatch(PATTERN) do
        local lower = name:lower()
        if not KNOWN[lower] and not seen[lower] then
            seen[lower] = true
            out[#out + 1] = name
        end
    end

    return out
end

-- one plain line, for anywhere that would print a rich text tag rather than obey it.
function QSF_Text.plain(text)
    if type(text) ~= "string" then return "" end

    local flat = text:gsub("<[^<>]*>", " ")
    flat = flat:gsub("%s+", " ")
    flat = flat:gsub("^ ", "")
    flat = flat:gsub(" $", "")

    return flat
end

-- cut at a word, for somewhere with room for a sentence and not a paragraph.
function QSF_Text.clip(text, limit)
    if #text <= limit then return text end

    local cut = text:sub(1, limit)
    local space = cut:find(" [^ ]*$")
    -- a single word longer than half the room is cut where it stands.
    if space and space > limit / 2 then cut = cut:sub(1, space - 1) end

    return cut .. "..."
end
