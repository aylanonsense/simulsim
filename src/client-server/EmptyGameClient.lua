local EmptyGameClient = {}
function EmptyGameClient:new()
  return {
    -- Public vars
    clientId = nil,
    data = {},

    -- Public methods
    connect = function(self, handshake) end,
    disconnect = function(self, reason) end,
    isConnected = function(self) end,
    isConnecting = function(self) end,
    fireEvent = function(self, eventType, eventData, params) end,
    setInputs = function(self, inputs, params) end,
    getGame = function(self) end,
    getGameWithoutPrediction = function(self) end,
    update = function(self, dt) end,
    simulateNetworkConditions = function(self, params) end,
    getFramesOfLatency = function(self) end,
    syncEntityState = function(self, entity, presentState, futureState) end,
    syncGameData = function(self, presentData, futureData) end,
    isEntityUsingClientSidePrediction = function(self, entity) end,

    -- Callback methods
    onConnect = function(self, callback) end,
    onConnectFailure = function(self, callback) end,
    onDisconnect = function(self, callback) end
  }
end

return EmptyGameClient
