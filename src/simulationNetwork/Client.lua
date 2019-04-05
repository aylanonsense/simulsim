-- Load dependencies
local SimulationRunner = require 'src/simulation/SimulationRunner'
local OffsetOptimizer = require 'src/simulationNetwork/OffsetOptimizer'
local stringUtils = require 'src/utils/string'

local Client = {}
function Client:new(params)
  params = params or {}
  local conn = params.conn
  local framesBetweenFlushes = params.framesBetweenFlushes or 0
  local simulationDefinition = params.simulationDefinition

  local simulation = simulationDefinition:new()
  local runner = SimulationRunner:new({
    simulation = simulation
  })
  local timeSyncOptimizer = OffsetOptimizer:new()
  local latencyOptimizer = OffsetOptimizer:new()

  local client = {
    -- Private vars
    _conn = conn,
    _status = 'disconnected',
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _simulation = simulation,
    _runner = runner,
    _timeSyncOptimizer = timeSyncOptimizer,
    _latencyOptimizer = latencyOptimizer,
    _handshake = nil,
    _framesOfLatency = 0,

    -- Public vars
    clientId = nil,
    data = {},
    framesBetweenFlushes = framesBetweenFlushes,
    framesUntilNextFlush = framesBetweenFlushes,

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
    fireEvent = function(self, eventType, eventData, params, isInputEvent)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        -- Create a new event
        local event = {
          id = 'client-' .. self.clientId .. '-' .. stringUtils.generateRandomString(10),
          frame = self._simulation.frame + self._framesOfLatency + 1,
          type = eventType,
          data = eventData,
          isInputEvent = isInputEvent or false,
          clientMetadata = {
            clientId = self.clientId,
            frameSent = self._simulation.frame,
            expectedFrameReceived = self._simulation.frame + self._framesOfLatency,
            framesOfLatency = self._framesOfLatency
          }
        }
        -- Send the event to the server
        self._conn:buffer({
          type = 'event',
          event = event
        }, reliable)
        -- Send immediately if we're not buffering
        if self.framesBetweenFlushes == 0 then
          self:flush()
        end
        -- Return the event
        return event
      end
    end,
    setInputs = function(self, inputs, params)
      self:fireEvent('set-inputs', inputs, params, true)
    end,
    flush = function(self, reliable)
      if self._status == 'connected' then
        self._conn:flush(reliable)
      end
    end,
    getSimulation = function(self)
      return self._simulation
    end,
    update = function(self, dt)
      -- Update the simulation (via the simulation runner)
      local df = self._runner:update(dt)
      -- Update the timing and latency optimizers
      self._timeSyncOptimizer:update(dt, df)
      self._latencyOptimizer:update(dt, df)
      -- Rewind or fast forward the simulation to get it synced with the server
      local timeAdjustment = self._timeSyncOptimizer:getRecommendedAdjustment()
      if timeAdjustment ~= 0 then
        -- TODO handle excessively large time adjustments
        if timeAdjustment > 0 then
          self._runner:fastForward(timeAdjustment)
        elseif timeAdjustment < 0 then
          self._runner:rewind(-timeAdjustment)
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
        self._framesOfLatency = self._framesOfLatency + latencyAdjustment
        self._latencyOptimizer:reset()
      end
      -- Flush the client's messages every so often
      self.framesUntilNextFlush = self.framesUntilNextFlush - df
      if self.framesUntilNextFlush <= 0 then
        self.framesUntilNextFlush = self.framesBetweenFlushes
        self:flush()
      end
    end,
    simulateNetworkConditions = function(self, params)
      self._conn:setNetworkConditions(params)
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
        self._framesOfLatency = math.ceil(self._conn:getLatency() / 60)
        -- Set the initial state of the client-side simulation
        self._runner:reset()
        self._runner:setState(state)
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
        self:_recordEventOffsets(event)
        self:_applyEvent(event)
      end
    end,
    _handleRejectEvent = function(self, event)
      if self._status == 'connected' then
        self:_recordEventOffsets(event)
        self:_unapplyEvent(event)
      end
    end,
    _applyEvent = function(self, event)
      return self._runner:applyEvent(event)
    end,
    _unapplyEvent = function(self, event)
      return self._runner:unapplyEvent(event)
    end,
    _recordEventOffsets = function(self, event)
      -- Record receive offsets
      self._timeSyncOptimizer:recordOffset(event.frame - self._simulation.frame - 1)
      -- Record send offsets
      if event.clientMetadata and event.clientMetadata.clientId == self.clientId and event.clientMetadata.framesOfLatency == self._framesOfLatency then
        if event.serverMetadata and event.serverMetadata.frameReceived then
          self._latencyOptimizer:recordOffset(event.clientMetadata.expectedFrameReceived - event.serverMetadata.frameReceived)
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
    end
  end)

  return client
end

return Client
