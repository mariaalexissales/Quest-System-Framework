----------
--ESTRAL--
----------

require "QSF_Core"

-- the only file that knows whether there is a server on the other end of the wire.
--
-- in singleplayer there is no remote, so a send is just a function call into the handler
-- that would have received it. that means singleplayer runs the identical accept, claim
-- and reward code the dedicated server runs, and every rule gets exercised on every
-- launch rather than only when somebody hosts.

QSF = QSF or {}
QSF_Net = QSF_Net or {}

function QSF_Net.hasRemoteServer()
    return QSF.hasRemoteServer()
end

-- handlers are looked up at call time, never cached. shared/ loads before client/ and
-- server/, so at this file's load time neither dispatcher exists yet.
local function QSF_serverHandler(command)
    return QSF_Commands and QSF_Commands.handlers and QSF_Commands.handlers[command]
end

local function QSF_clientHandler()
    return QSF_ClientState and QSF_ClientState.onCommand
end

function QSF_Net.toServer(command, args)
    args = args or {}

    if QSF_Net.hasRemoteServer() then
        sendClientCommand(getPlayer(), QSF.MODULE, command, args)
        return
    end

    local handler = QSF_serverHandler(command)
    if not handler then
        QSF.warn("no server handler for " .. tostring(command))
        return
    end

    -- loopback still goes through pcall, so a bug in a handler cannot take down the
    -- caller's frame the way a raw call would.
    local ok, err = pcall(handler, getPlayer(), args)
    if not ok then QSF.warn("server handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end

function QSF_Net.toClient(player, command, args)
    args = args or {}

    if isServer() then
        sendServerCommand(player, QSF.MODULE, command, args)
        return
    end

    local handler = QSF_clientHandler()
    if not handler then return end

    local ok, err = pcall(handler, QSF.MODULE, command, args)
    if not ok then QSF.warn("client handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end

function QSF_Net.toAll(command, args)
    args = args or {}

    if isServer() then
        sendServerCommand(QSF.MODULE, command, args)
        return
    end

    local handler = QSF_clientHandler()
    if not handler then return end

    local ok, err = pcall(handler, QSF.MODULE, command, args)
    if not ok then QSF.warn("client handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end
