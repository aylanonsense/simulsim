local EmptyGameServer = {}
function EmptyGameServer:new(params)
  return {
    -- Public methods
    startListening = function(self) end,
    isListening = function(self) end,
    getClientById = function(self, clientId) end,
    getClients = function(self) return {} end,
    fireEvent = function(self, eventType, eventData, params) end,
    getSimulation = function(self) end,
    update = function(self, dt) end,

    -- Overridable methods
    handleConnectRequest = function(self, client, handshake, accept, reject) end,
    shouldSendEventToClient = function(self, client, event) end,
    shouldAcceptEventFromClient = function(self, client, event) end,

    -- Callback methods
    onConnect = function(self, callback) end
  }
end

return EmptyGameServer
