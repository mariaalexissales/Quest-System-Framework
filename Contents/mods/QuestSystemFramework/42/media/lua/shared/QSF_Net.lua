----------
--ESTRAL--
----------

require "QSF_Core"

QSF_Net = QSF_Net or {}

-- a dedicated server's network, which is not there until the server has started.
QSF_Net.up = QSF_Net.up or false

-- looked up at call time: shared/ loads before client/ and server/, so neither dispatcher
-- exists yet when this file runs.
local function QSF_serverHandler(command)
    return QSF_Commands and QSF_Commands.handlers and QSF_Commands.handlers[command]
end

-- the singleplayer leg of anything sent to a client: there is nobody to send to, so it is
-- a direct call into the client's own dispatcher.
local function QSF_deliver(command, args)
    local handler = QSF_ClientState and QSF_ClientState.onCommand
    if not handler then return end

    local ok, err = pcall(handler, QSF.MODULE, command, args)
    if not ok then QSF.warn("client handler " .. tostring(command) .. " failed: " .. tostring(err)) end
end

-- with no remote server the send is a direct call into the handler that would have
-- received it, so singleplayer runs the same accept, claim and reward code the server does.
function QSF_Net.toServer(command, args)
    args = args or {}

    if QSF.hasRemoteServer() then
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

    QSF_deliver(command, args)
end

function QSF_Net.toAll(command, args)
    args = args or {}

    if isServer() then
        -- global mod data is ready before the network is, and sending to everybody then
        -- throws. nobody is on yet, and whoever joins is sent the lot.
        if QSF_Net.up then sendServerCommand(QSF.MODULE, command, args) end
        return
    end

    QSF_deliver(command, args)
end

Events.OnServerStarted.Add(function() QSF_Net.up = true end)
