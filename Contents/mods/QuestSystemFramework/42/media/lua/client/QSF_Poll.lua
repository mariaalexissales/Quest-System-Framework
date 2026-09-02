----------
--ESTRAL--
----------

require "QSF_Core"
require "QSF_Rules"
require "QSF_ClientState"

QSF = QSF or {}
QSF_Poll = QSF_Poll or {}

local POLL_MS = 2000
local CLAIM_MS = 10000

local lastPoll = 0
local lastClaim = {}

-- there is no "player gained an item" event, so collect progress is polled. the counts
-- never leave this machine: the server re-derives its own at turn-in.
function QSF_Poll.scan(player)
    local wanted = QSF_Rules.wantedItems(QSF_ClientState.defs, QSF_ClientState.state)
    local counts = {}
    local inventory = player:getInventory()

    for fullType in pairs(wanted) do
        -- Recurse, or everything in a bag goes uncounted.
        counts[fullType] = inventory:getItemCountRecurse(fullType)
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

    -- EveryOneMinute runs on game time, which sprints when the player sleeps, so the real
    -- clock is what actually paces this.
    local now = getTimestampMs()
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
                    -- a nudge, not a claim. the server checks the lot again itself.
                    QSF_ClientState.claim(key)
                end
            end
        end
    end
end

Events.EveryOneMinute.Add(QSF_tick)
