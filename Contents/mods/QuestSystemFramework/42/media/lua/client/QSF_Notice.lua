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
    NotRunning = "IGUI_QSF_Refused_NotRunning",
    NothingToGive = "IGUI_QSF_Refused_NothingToGive",
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

-- what each piece of news reads as, whether it is good news, and which part of it goes in
-- the line. a quest of the player's own is named from their list. a global quest's title
-- comes with the news: by the time somebody is paid for one it may have been taken out of
-- the files, and their list with it.
local NOTICES = {
    accepted = { text = "IGUI_QSF_Notice_Accepted", good = true, names = "quest" },
    completed = { text = "IGUI_QSF_Notice_Completed", good = true, names = "quest" },
    reloaded = { text = "IGUI_QSF_Notice_Reloaded", good = true },
    globalStarted = { text = "IGUI_QSF_Notice_GlobalStarted", good = true, names = "title" },
    globalCompleted = { text = "IGUI_QSF_Notice_GlobalCompleted", good = true, names = "title" },
    globalExpired = { text = "IGUI_QSF_Notice_GlobalExpired", good = false, names = "title" },
    globalGave = { text = "IGUI_QSF_Notice_GlobalGave", good = true, names = "count" },
    globalPaid = { text = "IGUI_QSF_Notice_GlobalPaid", good = true, names = "title" },
    globalConsoled = { text = "IGUI_QSF_Notice_GlobalConsoled", good = true, names = "title" },
}

-- returns the line, and whether it is good news.
local function QSF_wording(args)
    local def = args.key and QSF_ClientState.defs[args.key] or nil

    if args.kind == "refused" then return QSF_refusal(args, def), false end

    local kind = args.kind
    -- paid one of two things, depending on how it ended.
    if kind == "globalPaid" and args.outcome ~= "completed" then kind = "globalConsoled" end

    local notice = NOTICES[kind]
    if not notice then return nil end

    if not notice.names then return getText(notice.text), notice.good end

    local name = args[notice.names]
    if notice.names == "quest" then name = def and def.title or args.key end

    return getText(notice.text, tostring(name)), notice.good
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
