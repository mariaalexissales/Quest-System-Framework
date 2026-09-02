----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_ClientState"

-- there is no "player gained an item" event in the game, so collect objectives are
-- polled. this runs on the client and never sends counts anywhere: the numbers are for
-- the window, and the server re-derives its own at turn-in regardless. the only thing
-- that leaves this file is a nudge saying a quest looks finished.

QSF = QSF or {}
QSF_Poll = QSF_Poll or {}

local POLL_MS = 2000
local CLAIM_MS = 10000

local lastPoll = 0
local lastClaim = {}

local function QSF_nowMs()
    local ok, ms = pcall(function() return getTimestampMs() end)
    if ok and ms then return ms end
    return 0
end

-- asks the engine once per wanted item type rather than once per objective, so two
-- quests both wanting nails cost one call between them.
function QSF_Poll.scan(player)
    local wanted = QSF_Rules.wantedItems(QSF_ClientState.defs, QSF_ClientState.state)
    local counts = {}
    local inventory = player:getInventory()

    for fullType in pairs(wanted) do
        -- Recurse, always. plain getItemCount ignores anything in a bag, and a bag is
        -- exactly where a player keeps the twenty nails a quest asked for.
        local ok, n = pcall(function() return inventory:getItemCountRecurse(fullType) end)
        counts[fullType] = (ok and n) or 0
    end

    return counts
end

local function QSF_changed(before, after)
    for key, value in pairs(after) do
        if before[key] ~= value then return true end
    end
    for key in pairs(before) do
        if after[key] == nil then return true end
    end
    return false
end

local function QSF_tick()
    if not QSF_ClientState.ready then return end

    local player = getPlayer()
    if not player then return end

    -- EveryOneMinute fires on game time, which runs fast when the player sleeps or
    -- fast-forwards, so the real clock is what actually paces this.
    local now = QSF_nowMs()
    if now - lastPoll < POLL_MS then return end
    lastPoll = now

    local counts = QSF_Poll.scan(player)

    if QSF_changed(QSF_ClientState.collect, counts) then
        QSF_ClientState.collect = counts
        QSF_ClientState.touch()
    else
        QSF_ClientState.collect = counts
    end

    for key, rec in pairs(QSF_ClientState.state) do
        if rec.status == "active" then
            local def = QSF_ClientState.defs[key]

            if def and def.autoComplete and QSF_Rules.isComplete(def, rec, counts) then
                if now - (lastClaim[key] or 0) >= CLAIM_MS then
                    lastClaim[key] = now
                    -- a nudge, not a claim. the server checks everything again itself.
                    QSF_ClientState.claim(key)
                end
            end
        end
    end
end

Events.EveryOneMinute.Add(QSF_tick)
