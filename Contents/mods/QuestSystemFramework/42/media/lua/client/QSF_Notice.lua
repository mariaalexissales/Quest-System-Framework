----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_ClientState"
require "QSF_Detail"

QSF_Notice = QSF_Notice or {}

-- refusals the log never has to word, because it never offers the thing in the first place.
local REFUSED = {
    Changed = "IGUI_QSF_Refused_Changed",
    OffMap = "IGUI_QSF_Refused_OffMap",
    KeyTaken = "IGUI_QSF_Place_KeyTaken",
    BadNpc = "IGUI_QSF_Refused_BadNpc",
    WriteFailed = "IGUI_QSF_Refused_WriteFailed",
}

-- the window was a click behind, and what was asked for has already happened. telling a
-- player their quest could not be taken because they have just taken it helps nobody.
local SILENT = { AlreadyActive = true, NotActive = true }

local function QSF_refusal(args, def)
    if SILENT[args.reason] then return nil end

    if args.reason == "TooFar" then
        local giver = def and def.giver and QSF_ClientState.npcs[def.giver] or nil
        return getText("IGUI_QSF_Refused_TooFar", giver and giver.name or (def and def.title) or "")
    end

    if REFUSED[args.reason] then return getText(REFUSED[args.reason]) end

    -- anything that would lock a row in the log is worded the way the log words it.
    return QSF_Detail.reasonText(args.reason, args.detail, args.extra) or getText("IGUI_QSF_Refused_Generic")
end

-- returns the line, and whether it is good news.
local function QSF_wording(args)
    local def = args.key and QSF_ClientState.defs[args.key] or nil
    local title = def and def.title or tostring(args.key)

    if args.kind == "accepted" then return getText("IGUI_QSF_Notice_Accepted", title), true end
    if args.kind == "completed" then return getText("IGUI_QSF_Notice_Completed", title), true end
    if args.kind == "reloaded" then return getText("IGUI_QSF_Notice_Reloaded"), true end
    if args.kind == "refused" then return QSF_refusal(args, def), false end

    return nil
end

-- over the player's head, the way the game says the inventory is full. a refusal used to
-- look like a button that did nothing.
function QSF_Notice.show(args)
    if type(args) ~= "table" then return end

    local player = getPlayer()
    if not player then return end

    local text, good = QSF_wording(args)
    if not text then return end

    if good then
        HaloTextHelper.addGoodText(player, text)
    else
        HaloTextHelper.addBadText(player, text)
    end
end
