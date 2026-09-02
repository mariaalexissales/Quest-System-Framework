----------
--ESTRAL--
----------

-- project zomboid ships no lua json parser. strict about structure, forgiving about the
-- three things a hand-written file always has wrong: a notepad bom, // comments, and a
-- trailing comma.

QSF = QSF or {}
QSF_Json = QSF_Json or {}

local ESCAPES = {
    ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b",
    f = "\f", n = "\n", r = "\r", t = "\t",
}

-- kahlua's string.char takes one byte at a time. above the basic plane folds to a ?.
local function QSF_utf8(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
    elseif code < 0x10000 then
        return string.char(0xE0 + math.floor(code / 0x1000),
                           0x80 + (math.floor(code / 0x40) % 0x40),
                           0x80 + (code % 0x40))
    end
    return "?"
end

-- a character scan, not a gsub: a naive comment strip eats the slashes in any url in a
-- description, and a naive comma strip eats commas in prose. only the in-string state
-- tells code from content.
local function QSF_prepass(text)
    -- notepad writes a bom and the parser would choke on it as a stray character.
    if text:sub(1, 3) == "\239\187\191" then text = text:sub(4) end

    local out, i, n = {}, 1, #text
    local inString, escaped = false, false

    while i <= n do
        local c = text:sub(i, i)

        if inString then
            out[#out + 1] = c
            if escaped then
                escaped = false
            elseif c == "\\" then
                escaped = true
            elseif c == '"' then
                inString = false
            end
            i = i + 1
        elseif c == '"' then
            inString = true
            out[#out + 1] = c
            i = i + 1
        elseif c == "/" and text:sub(i + 1, i + 1) == "/" then
            -- the newline is kept so reported line numbers still match the file.
            local stop = text:find("\n", i, true)
            if not stop then break end
            i = stop
        elseif c == "/" and text:sub(i + 1, i + 1) == "*" then
            local stop = text:find("*/", i + 2, true)
            if not stop then break end
            -- replaced by its own newlines, again to keep line numbers matching.
            for _ in text:sub(i, stop + 1):gmatch("\n") do out[#out + 1] = "\n" end
            i = stop + 2
        elseif c == "," then
            -- a comma is trailing when the next meaningful character closes the container.
            local nextAt = text:find("[^%s]", i + 1)
            local nextChar = nextAt and text:sub(nextAt, nextAt) or nil
            if nextChar == "}" or nextChar == "]" then
                i = i + 1
            else
                out[#out + 1] = c
                i = i + 1
            end
        else
            out[#out + 1] = c
            i = i + 1
        end
    end

    return table.concat(out)
end

local Parser = {}
Parser.__index = Parser

function Parser.new(text)
    return setmetatable({ text = text, pos = 1, len = #text }, Parser)
end

function Parser:lineAt(pos)
    local line = 1
    for _ in self.text:sub(1, pos):gmatch("\n") do line = line + 1 end
    return line
end

function Parser:fail(message)
    error("line " .. self:lineAt(self.pos) .. ": " .. message, 0)
end

function Parser:skip()
    local at = self.text:find("[^ \t\r\n]", self.pos)
    self.pos = at or (self.len + 1)
end

function Parser:peek()
    return self.text:sub(self.pos, self.pos)
end

function Parser:parseString()
    self.pos = self.pos + 1
    local out = {}

    while true do
        if self.pos > self.len then self:fail("unterminated string") end
        local c = self.text:sub(self.pos, self.pos)

        if c == '"' then
            self.pos = self.pos + 1
            return table.concat(out)
        elseif c == "\\" then
            local esc = self.text:sub(self.pos + 1, self.pos + 1)
            if esc == "u" then
                local hex = self.text:sub(self.pos + 2, self.pos + 5)
                local code = tonumber(hex, 16)
                if not code then self:fail("bad unicode escape") end
                out[#out + 1] = QSF_utf8(code)
                self.pos = self.pos + 6
            elseif ESCAPES[esc] then
                out[#out + 1] = ESCAPES[esc]
                self.pos = self.pos + 2
            else
                self:fail("unknown escape character")
            end
        else
            out[#out + 1] = c
            self.pos = self.pos + 1
        end
    end
end

function Parser:parseNumber()
    local span = self.text:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", self.pos)
    local value = span and tonumber(span)
    if not value then self:fail("bad number") end
    self.pos = self.pos + #span
    return value
end

function Parser:parseArray()
    self.pos = self.pos + 1
    local out = {}

    self:skip()
    if self:peek() == "]" then self.pos = self.pos + 1 return out end

    while true do
        local value = self:parseValue()
        -- compacting beats a hole that breaks every ipairs and # downstream.
        if value ~= nil then out[#out + 1] = value end

        self:skip()
        local c = self:peek()
        if c == "," then
            self.pos = self.pos + 1
        elseif c == "]" then
            self.pos = self.pos + 1
            return out
        else
            self:fail("expected a comma or a closing bracket in array")
        end
    end
end

function Parser:parseObject()
    self.pos = self.pos + 1
    local out = {}

    self:skip()
    if self:peek() == "}" then self.pos = self.pos + 1 return out end

    while true do
        self:skip()
        if self:peek() ~= '"' then self:fail("expected a quoted key") end
        local key = self:parseString()

        self:skip()
        if self:peek() ~= ":" then self:fail("expected a colon after key " .. key) end
        self.pos = self.pos + 1

        -- null decodes to nil, so the key is absent and the default applies.
        out[key] = self:parseValue()

        self:skip()
        local c = self:peek()
        if c == "," then
            self.pos = self.pos + 1
        elseif c == "}" then
            self.pos = self.pos + 1
            return out
        else
            self:fail("expected a comma or a closing brace in object")
        end
    end
end

function Parser:parseValue()
    self:skip()
    local c = self:peek()

    if c == "" then self:fail("unexpected end of file") end
    if c == "{" then return self:parseObject() end
    if c == "[" then return self:parseArray() end
    if c == '"' then return self:parseString() end

    if self.text:sub(self.pos, self.pos + 3) == "true" then
        self.pos = self.pos + 4
        return true
    end
    if self.text:sub(self.pos, self.pos + 4) == "false" then
        self.pos = self.pos + 5
        return false
    end
    if self.text:sub(self.pos, self.pos + 3) == "null" then
        self.pos = self.pos + 4
        return nil
    end
    if c:match("[%-%d]") then return self:parseNumber() end

    self:fail("unexpected character " .. c)
end

-- returns the value, or nil plus a message. never raises.
function QSF_Json.decode(text)
    if type(text) ~= "string" or text:match("^%s*$") then
        return nil, "file is empty"
    end

    local parser = Parser.new(QSF_prepass(text))

    local ok, result = pcall(function()
        local value = parser:parseValue()
        parser:skip()
        if parser.pos <= parser.len then
            parser:fail("trailing content after the top-level value")
        end
        return value
    end)

    if not ok then return nil, tostring(result) end
    if result == nil then return nil, "top-level value is null" end
    return result
end
