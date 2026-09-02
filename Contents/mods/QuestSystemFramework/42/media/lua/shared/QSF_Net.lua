----------
--ESTRAL--
----------

require "QSF_Core"

QSF = QSF or {}
QSF_Net = QSF_Net or {}

function QSF_Net.hasRemoteServer()
    return QSF.hasRemoteServer()
end

-- looked up at call time: shared/ loads before client/ and server/, so neither dispatcher
-- exists yet when this file runs.
local function QSF_serverHandler(command)
    return QSF_Commands and QSF_Commands.handlers and QSF_Commands.handlers[command]
end

local function QSF_clientHandler()
    return QSF_ClientState and QSF_ClientState.onCommand
end

-- with no remote server the send is a direct call into the handler that would have
-- received it, so singleplayer runs the same accept, claim and reward code the server does.
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
