local EmptyGameClient = {}
function EmptyGameClient:new()
  return {
    -- Public vars
    clientId = nil,
    data = {},
    game = {},
    gameWithoutSmoothing = {},
    gameWithoutPrediction = {},

    -- Public methods
    connect = function(self, handshake) end,
    disconnect = function(self, reason) end,
    isConnecting = function(self) end,
    isConnected = function(self) end,
    isStable = function(self) end,
    getFramesOfLatency = function(self) end,
    fireEvent = function(self, eventType, eventData, params) end,
    setInputs = function(self, inputs, params) end,
    update = function(self, dt) end,
    moveForwardOneFrame = function(self, dt) end,
    simulateNetworkConditions = function(self, params) end,
    syncEntity = function(self, game, entity, candidateEntity, isPrediction) end,
    syncInputs = function(self, game, inputs, candidateInputs, isPrediction) end,
    syncData = function(self, game, data, candidateData, isPrediction) end,
    smoothEntity = function(self, game, entity, idealEntity) end,
    smoothInputs = function(self, game, inputs, idealInputs) end,
    smoothData = function(self, game, data, idealData) end,
    isEntityUsingPrediction = function(self, entity) end,

    -- Callback methods
    onConnect = function(self, callback) end,
    onConnectFailure = function(self, callback) end,
    onDisconnect = function(self, callback) end,
    onStabilize = function(self, callback) end,
    onDestabilize = function(self, callback) end
  }
end

return EmptyGameClient
