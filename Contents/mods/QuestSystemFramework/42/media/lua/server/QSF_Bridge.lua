----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Json"
require "QSF_Defs"

if not QSF.isAuthority() then return end

-- everything that faces outside the game. the rest of the server says what happened and
-- knows nothing about who is listening. whatever wants to tell the world, a file a discord
-- bot reads or another mod altogether, asks to be told here.
QSF_Bridge = QSF_Bridge or {}

-- event to who asked for it. kept when this file is run again, so a reloadlua does not
-- leave the server telling nobody.
QSF_Bridge.listeners = QSF_Bridge.listeners or {}

-- seconds, which is what everything outside the game counts in.
function QSF_Bridge.seconds(ms)
    return ms and math.floor(ms / 1000) or nil
end

-- name is who is asking. asking again under the same name replaces what was there rather
-- than adding to it, so a file that is run twice does not hear everything twice.
function QSF_Bridge.on(event, name, listener)
    QSF_Bridge.listeners[event] = QSF_Bridge.listeners[event] or {}
    QSF_Bridge.listeners[event][name] = listener
end

-- what happened, to everybody who asked. each is told the event's name and when, on top of
-- whatever came with it:
--   questAccepted      username, key, title
--   questCompleted     username, key, title, turnins, rolled
--   questAbandoned     username, key, title
--   globalStarted      key, title, run, ends
--   globalContributed  username, key, title, amount
--   globalEnded        key, title, run, outcome, participants, owed
--   globalPaid         username, key, title, run, outcome, rolled
--   reloaded           quests, global, npcs
-- rolled is what a random reward came up as, a list of item and count, and is empty for
-- a quest with none. nothing is said per kill. a listener that throws is somebody else's code, and does not
-- get to take a turn-in or a payout down with it.
function QSF_Bridge.emit(event, payload)
    local listeners = QSF_Bridge.listeners[event]
    if not listeners then return end

    payload = payload or {}
    payload.event = event
    payload.at = QSF_Bridge.seconds(getTimestampMs())

    for name, listener in pairs(listeners) do
        local ok, err = pcall(listener, payload)
        if not ok then
            QSF.warn("bridge listener " .. tostring(name) .. " failed on " .. event .. ": " .. tostring(err))
        end
    end
end

-- the order they are written in, which is the order somebody reading the file wants.
local REPORT_FIELDS = {
    "written", "global", "unpaid",
    "key", "title", "run", "status", "outcome", "started", "ends", "ended",
    "objectives", "participants", "players",
    "type", "item", "have", "need",
    "username", "contributed", "eligible", "owed",
}

-- the latest run of every global quest that has ever started, with everybody who took
-- part, and then every payout still waiting on somebody, earlier runs included.
function QSF_Bridge.report()
    local data = QSF_Global.ensure()

    local waiting, unpaid = {}, {}

    for index, entry in ipairs(data.owed) do
        local names = QSF.sortedKeys(entry.to)
        for _, username in ipairs(names) do
            waiting[entry.key .. "/" .. entry.run .. "/" .. username] = true
        end

        unpaid[index] = { key = entry.key, run = entry.run, outcome = entry.outcome, players = names }
    end

    local quests = {}

    for _, key in ipairs(QSF.sortedKeys(data.runs)) do
        local run, def = data.runs[key], QSF_Defs.global[key]

        local objectives = {}
        for i, obj in ipairs(def and def.objectives or {}) do
            objectives[i] = { type = obj.type, item = obj.item, have = run.prog[i] or 0, need = obj.count }
        end

        local participants = {}
        for i, username in ipairs(QSF.sortedKeys(run.players)) do
            local units = run.players[username]

            participants[i] = {
                username = username,
                contributed = units,
                eligible = units >= (def and def.minContribution or 1),
                owed = waiting[key .. "/" .. run.run .. "/" .. username] == true,
            }
        end

        quests[#quests + 1] = {
            key = key,
            title = def and def.title or key,
            run = run.run,
            status = run.status,
            started = QSF_Bridge.seconds(run.started),
            ends = QSF_Bridge.seconds(run.ends),
            ended = QSF_Bridge.seconds(run.ended),
            objectives = objectives,
            participants = participants,
        }
    end

    return { written = QSF_Bridge.seconds(getTimestampMs()), global = quests, unpaid = unpaid }
end

function QSF_Bridge.write()
    return QSF_Defs.writeFile(QSF.GLOBAL_FILE, QSF_Json.encode(QSF_Bridge.report(), REPORT_FIELDS) .. "\n")
end

-- what QSF_GlobalExport.lua runs. an empty server stops the game clock and the minute tick
-- with it, so the overdue are settled first: whoever asks should not be told a quest that
-- ran out yesterday is still going.
function QSF_Bridge.export()
    if not QSF_Global or not QSF_Global.ready then return false end

    QSF_Global.tick()

    if not QSF_Bridge.write() then return false end

    QSF.log("global quest report written to Zomboid/Lua/" .. QSF.DIR .. "/" .. QSF.GLOBAL_FILE)
    return true
end

-- the moment the list of who took part is worth having outside the game.
QSF_Bridge.on("globalEnded", "report", QSF_Bridge.write)
