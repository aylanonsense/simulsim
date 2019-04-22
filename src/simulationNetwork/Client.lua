-- Load dependencies
local SimulationRunner = require 'src/simulation/SimulationRunner'
local OffsetOptimizer = require 'src/simulationNetwork/OffsetOptimizer'
local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'

local Client = {}
function Client:new(params)
  params = params or {}
  local conn = params.conn
  local simulationDefinition = params.simulationDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 0
  local framesBetweenPings = params.framesBetweenPings or 15

  -- Create a simulation for the client and a runner for it
  local clientRunner = SimulationRunner:new({
    simulation = simulationDefinition:new()
  })
  local serverRunner = SimulationRunner:new({
    simulation = simulationDefinition:new()
  })

  -- Create offset optimizers to minimize time desync and latency
  local timeSyncOptimizer = OffsetOptimizer:new()
  local latencyOptimizer = OffsetOptimizer:new()

  local client = {
    -- Private config vars
    _framesBetweenPings = framesBetweenPings,
    _framesBetweenFlushes = framesBetweenFlushes,

    -- Private vars
    _conn = conn,
    _status = 'disconnected',
    _clientRunner = clientRunner,
    _serverRunner = serverRunner,
    _timeSyncOptimizer = timeSyncOptimizer,
    _latencyOptimizer = latencyOptimizer,
    _handshake = nil,
    _framesOfLatency = 0,
    _framesUntilNextPing = framesBetweenPings,
    _framesUntilNextFlush = framesBetweenFlushes,
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},

    -- Public vars
    clientId = nil,
    data = {},

    -- Public methods
    connect = function(self, handshake)
      if self._status == 'disconnected' then
        self._status = 'connecting'
        self._handshake = handshake
        self._conn:connect()
      end
    end,
    disconnect = function(self, reason)
      if self._status == 'connecting' then
        self.clientId = nil
        self.data = {}
        self._status = 'disconnected'
        self._conn:disconnect('Manual disconnect')
      elseif self._status == 'connected' then
        -- Let the server know why the client's disconnecting
        self._conn:send({
          type = 'disconnect-request',
          reason = reason
        }, true)
        self.clientId = nil
        self.data = {}
        self._status = 'disconnected'
        self._conn:disconnect('Manual disconnect')
        -- Trigger disconnect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Manual disconnect')
        end
      end
    end,
    isConnected = function(self)
      return self._status == 'connected'
    end,
    isConnecting = function(self)
      return self._status == 'connecting' or self._status == 'handshaking'
    end,
    fireEvent = function(self, eventType, eventData, params)
      params = params or {}
      local reliable = params.reliable
      local isInputEvent = params.isInputEvent
      local predictClientSide = params.predictClientSide ~= false
      if self._status == 'connected' then
        -- Create a new event
        local event = {
          id = 'client-' .. self.clientId .. '-' .. stringUtils.generateRandomString(10),
          frame = self._clientRunner:getSimulation().frame + self._framesOfLatency + 1,
          type = eventType,
          data = eventData,
          isInputEvent = isInputEvent or false
        }
        self:_addClientMetadata(event)
        -- Apply a prediction of the event
        if predictClientSide then
          local serverEvent = tableUtils.cloneTable(event)
          self._serverRunner:applyEvent(serverEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5
          })
          local clientEvent = tableUtils.cloneTable(event)
          clientEvent.frame = self._clientRunner:getSimulation().frame + 1
          self._clientRunner:applyEvent(clientEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5,
            preserveFrame = true
          })
        end
        -- Send the event to the server
        self._conn:buffer({
          type = 'event',
          event = event
        }, reliable)
        -- Send immediately if we're not buffering
        if self._framesBetweenFlushes <= 0 then
          self:flush()
        end
        -- Return the event
        return event
      end
    end,
    setInputs = function(self, inputs, params)
      params = params or {}
      params.isInputEvent = true
      self:fireEvent('set-inputs', {
        clientId = self.clientId,
        inputs = inputs
      }, params)
    end,
    flush = function(self, reliable)
      if self._status == 'connected' then
        self._conn:flush(reliable)
      end
    end,
    getSimulation = function(self)
      return self._clientRunner:getSimulation()
    end,
    getSimulationWithoutPrediction = function(self)
      return self._serverRunner:getSimulation()
    end,
    update = function(self, dt)
      -- Update the simulation (via the simulation runner)
      local df = self._clientRunner:update(dt)
      self._serverRunner:update(dt)
      -- Update the timing and latency optimizers
      self._timeSyncOptimizer:update(dt, df)
      self._latencyOptimizer:update(dt, df)
      -- Rewind or fast forward the simulation to get it synced with the server
      local timeAdjustment = self._timeSyncOptimizer:getRecommendedAdjustment()
      if timeAdjustment ~= 0 then
        -- TODO handle excessively large time adjustments
        if timeAdjustment > 0 then
          self._clientRunner:fastForward(timeAdjustment)
          self._serverRunner:fastForward(timeAdjustment)
        elseif timeAdjustment < 0 then
          self._clientRunner:rewind(-timeAdjustment)
          self._serverRunner:rewind(-timeAdjustment)
        end
        self._timeSyncOptimizer:reset()
        local latencyAdjustment = -math.min(self._framesOfLatency, timeAdjustment)
        self._framesOfLatency = self._framesOfLatency + latencyAdjustment
        self._latencyOptimizer:applyAdjustment(latencyAdjustment)
      end
      -- Adjust latency to ensure messages are arriving on time server-side
      local latencyAdjustment = self._latencyOptimizer:getRecommendedAdjustment()
      if latencyAdjustment ~= 0 then
        -- TODO handle excessively large latency adjustments
        self._framesOfLatency = self._framesOfLatency - latencyAdjustment
        self._latencyOptimizer:reset()
      end
      -- Send a lazy ping every so often to guage latency accuracy
      self._framesUntilNextPing = self._framesUntilNextPing - df
      if self._framesUntilNextPing <= 0 then
        self._framesUntilNextPing = self._framesBetweenPings
        self:_ping()
      end
      -- Flush the client's messages every so often
      self._framesUntilNextFlush = self._framesUntilNextFlush - df
      if self._framesUntilNextFlush <= 0 then
        self._framesUntilNextFlush = self._framesBetweenFlushes
        self:flush()
      end
      -- Make sure we have enough recorded history to be operational
      if self._clientRunner.framesOfHistory > math.max(self._framesOfLatency + 10, 30) then
        self._clientRunner.framesOfHistory = self._clientRunner.framesOfHistory - 1
      else
        self._clientRunner.framesOfHistory = math.min(self._framesOfLatency + 10, 300)
      end
      self._serverRunner.framesOfHistory = self._clientRunner.framesOfHistory
    end,
    simulateNetworkConditions = function(self, params)
      self._conn:setNetworkConditions(params)
    end,
    getFramesOfLatency = function(self)
      return self._framesOfLatency
    end,
    syncEntityState = function(self, entity, presentState, futureState)
      return self:isEntityUsingClientSidePrediction(entity) and futureState or presentState
    end,
    syncSimulationData = function(self, presentData, futureData)
      return futureData
    end,
    isEntityUsingClientSidePrediction = function(self, entity)
      return false
    end,

    -- Private methods
    _handleConnect = function(self)
      if self._status == 'connecting' then
        self._status = 'handshaking'
        self._conn:send({
          type = 'connect-request',
          handshake = self._handshake
        }, true)
      end
    end,
    _handleConnectAccept = function(self, clientId, clientData, state)
      if self._status == 'handshaking' then
        self._status = 'connected'
        self.clientId = clientId
        self.data = clientData or {}
        self._framesOfLatency = math.ceil(60 * self._conn:getLatency() / 1000)
        -- Set the initial state of the client-side simulation
        self._clientRunner:reset()
        self._clientRunner:setState(state)
        self._serverRunner:reset()
        self._serverRunner:setState(state)
        -- Trigger connect callbacks
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
        end
      end
    end,
    _handleConnectReject = function(self, reason)
      if self._status ~= 'disconnected' then
        self._status = 'disconnected'
        self.clientId = nil
        self.data = {}
        self._conn:disconnect('Connection rejected')
        -- Trigger connect failure callbacks
        for _, callback in ipairs(self._connectFailureCallbacks) do
          callback(reason or 'Connection rejected')
        end
      end
    end,
    _handleDisconnect = function(self, reason)
      if self._status == 'connected' then
        self._status = 'disconnected'
        self.clientId = nil
        self.data = {}
        self._conn:disconnect()
        -- Trigger connect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Connection terminated')
        end
      elseif self._status == 'connecting' then
        self._status = 'disconnected'
        self.clientId = nil
        self.data = {}
        self._conn:disconnect()
      end
    end,
    _handleReceiveEvent = function(self, event)
      if self._status == 'connected' then
        self:_recordTimeSyncOffset(event)
        self:_recordLatencyOffset(event)
        self:_applyEvent(event)
      end
    end,
    _handleRejectEvent = function(self, event)
      if self._status == 'connected' then
        self:_recordTimeSyncOffset(event)
        self:_recordLatencyOffset(event)
        self:_unapplyEvent(event)
      end
    end,
    _handlePingResponse = function(self, ping)
      if self._status == 'connected' then
        self:_recordTimeSyncOffset(ping)
        self:_recordLatencyOffset(ping)
      end
    end,
    _handleStateSnapshot = function(self, state)
      if self._status == 'connected' then
        self._serverRunner:applyState(state)
        -- Predict the future game state based on where the server is right now
        local futureRunner = self._serverRunner:clone()
        futureRunner:fastForward(self._framesOfLatency)
        local presentSimulation = self._serverRunner:getSimulation()
        local futureSimulation = futureRunner:getSimulation()
        -- Use that to construct a state for the client predicted simulation
        local frame = presentSimulation.frame
        local inputs = tableUtils.cloneTable(presentSimulation.inputs)
        inputs[self.clientId] = futureSimulation.inputs[self.clientId]
        local data = self:syncSimulationData(presentSimulation.data, futureSimulation.data)
        local entities = {}
        -- Handle entities that exist in the future and may or may not exist currently
        for _, futureEntity in ipairs(futureSimulation.entities) do
          local entityId = futureSimulation:getEntityId(futureEntity)
          local futureState = futureSimulation:getStateFromEntity(futureEntity)
          local presentEntity = presentSimulation:getEntityById(entityId)
          local presentState = nil
          if presentEntity then
            presentState = presentSimulation:getStateFromEntity(presentEntity)
          end
          -- Decide whether to use the future state or present state for the entity
          local state = self:syncEntityState(futureEntity, presentState, futureState)
          if state then
            table.insert(entities, state)
          end
        end
        -- Handle entities that exist now but not in the future
        for _, presentEntity in ipairs(presentSimulation.entities) do
          local entityId = presentSimulation:getEntityId(presentEntity)
          local futureEntity = futureSimulation:getEntityById(entityId)
          if not futureEntity then
            local presentState = presentSimulation:getStateFromEntity(presentEntity)
            local state = self:syncEntityState(presentEntity, presentState, nil)
            if state then
              table.insert(entities, state)
            end
          end
        end
        -- Assemble the idealized state that features client-side prediction
        local state = {
          frame = frame,
          inputs = inputs,
          data = data,
          entities = entities
        }
        -- Apply this to the client runner
        self._clientRunner:applyState(state)
      end
    end,
    _applyEvent = function(self, event)
      self._serverRunner:applyEvent(event)
      return self._clientRunner:applyEvent(event)
    end,
    _unapplyEvent = function(self, event)
      self._serverRunner:unapplyEvent(event)
      return self._clientRunner:unapplyEvent(event)
    end,
    _ping = function(self, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        -- Send a ping to the server, no need to flush immediately since we want the buffer time to be accounted for
        self._conn:buffer({
          type = 'ping',
          ping = self:_addClientMetadata({})
        }, reliable)
      end
      -- But flush immediately if we have no auto-flushing
      if self._framesBetweenFlushes <= 0 then
        self:flush()
      end
    end,
    _addClientMetadata = function(self, obj)
      local frame = self._clientRunner:getSimulation().frame
      obj.clientMetadata = {
        clientId = self.clientId,
        frameSent = frame,
        expectedFrameReceived = frame + self._framesOfLatency,
        framesOfLatency = self._framesOfLatency
      }
      return obj
    end,
    _recordTimeSyncOffset = function(self, msg)
      self._timeSyncOptimizer:recordOffset(msg.frame - self._clientRunner:getSimulation().frame - 1)
    end,
    _recordLatencyOffset = function(self, msg)
      if msg.clientMetadata and msg.clientMetadata.clientId == self.clientId and msg.clientMetadata.framesOfLatency == self._framesOfLatency then
        if msg.serverMetadata and msg.serverMetadata.frameReceived then
          self._latencyOptimizer:recordOffset(msg.clientMetadata.expectedFrameReceived - msg.serverMetadata.frameReceived)
        end
      end
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onConnectFailure = function(self, callback)
      table.insert(self._connectFailureCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end
  }

  -- Bind events
  conn:onConnect(function()
    client:_handleConnect()
  end)
  conn:onDisconnect(function(reason)
    client:_handleDisconnect(reason)
  end)
  conn:onReceive(function(msg)
    if msg.type == 'connect-accept' then
      client:_handleConnectAccept(msg.clientId, msg.clientData, msg.state)
    elseif msg.type == 'connect-reject' then
      client:_handleConnectReject(msg.reason)
    elseif msg.type == 'force-disconnect' then
      client:_handleDisconnect(msg.reason)
    elseif msg.type == 'event' then
      client:_handleReceiveEvent(msg.event)
    elseif msg.type == 'reject-event' then
      client:_handleRejectEvent(msg.event)
    elseif msg.type == 'ping-response' then
      client:_handlePingResponse(msg.ping)
    elseif msg.type == 'state-snapshot' then
      client:_handleStateSnapshot(msg.state)
    end
  end)

  return client
end

return Client
