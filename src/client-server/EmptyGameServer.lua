local EmptyGameServer = {}
function EmptyGameServer:new(params)
  return {
    -- Public vars
    game = {},

    -- Public methods
    disconnect = function(self, reason) end,
    isConnected = function(self) end,
    moveForwardOneFrame = function(self, dt) end,
    onDisconnect = function(self, callback) end,
    startListening = function(self) end,
    isListening = function(self) end,
    getClientById = function(self, clientId) end,
    getClients = function(self) end,
    fireEvent = function(self, eventType, eventData, params) end,
    getGame = function(self) end,
    update = function(self, dt) end,
    moveForwardOneFrame = function(self, dt) end,

    -- Overridable methods
    handleConnectRequest = function(self, client, handshake, accept, reject) end,
    shouldSendEventToClient = function(self, client, event) end,
    shouldAcceptEventFromClient = function(self, client, event) end,
    generateStateSnapshotForClient = function(self, client) end,

    -- Callback methods
    onConnect = function(self, callback) end
  }
end

return EmptyGameServer
