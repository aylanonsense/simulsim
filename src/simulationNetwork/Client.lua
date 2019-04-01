-- Load dependencies
local SimulationRunner = require 'src/simulation/SimulationRunner'
local stringUtils = require 'src/utils/string'

local Client = {}
function Client:new(params)
  params = params or {}
  local conn = params.conn
  local simulationDefinition = params.simulationDefinition
  local simulation = simulationDefinition:new()
  local runner = SimulationRunner:new({
    simulation = simulation
  })

  local client = {
    -- Private vars
    _conn = conn,
    _status = 'disconnected',
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _simulation = simulation,
    _runner = runner,

    -- Public vars
    clientId = nil,
    data = {},

    -- Public methods
    connect = function(self)
      if self._status == 'disconnected' then
        self._status = 'connecting'
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
          type = 'client-disconnect',
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
      return self._status == 'connecting'
    end,
    fireEvent = function(self, eventType, eventData, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        -- Create a new event
        local event = {
          id = 'client-' .. self.clientId .. '-' .. stringUtils:generateRandomString(10),
          frame = self._simulation.frame, -- TODO + latency
          type = eventType,
          data = eventData
        }
        -- Send the event to the server
        self._conn:buffer({
          type = 'event',
          event = event
        }, reliable)
        -- Return the event
        return event
      end
    end,
    setInputs = function(self, inputs, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        -- Create a new event
        local event = {
          id = 'client-' .. self.clientId .. '-' .. stringUtils:generateRandomString(10),
          frame = self._simulation.frame, -- TODO + latency
          type = 'set-inputs',
          data = inputs,
          isInputEvent = true
        }
        -- Send the event to the server
        self._conn:buffer({
          type = 'event',
          event = event
        }, reliable)
        -- Return the event
        return event
      end
    end,
    flush = function(self, reliable)
      if self._status == 'connected' then
        self._conn:flush(reliable)
      end
    end,
    update = function(self, dt)
      self._runner:update(dt)
    end,

    -- Private methods
    _handleConnect = function(self, clientId, clientData, state)
      if self._status == 'connecting' then
        self._status = 'connected'
        self.clientId = clientId
        self.data = clientData or {}
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
        self:_applyEvent(event)
      end
    end,
    _handleRejectEvent = function(self, event)
      if self._status == 'connected' then
        self:_unapplyEvent(event)
      end
    end,
    _applyEvent = function(self, event)
      return self._runner:applyEvent(event)
    end,
    _unapplyEvent = function(self, event)
      return self._runner:unapplyEvent(event)
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
  conn:onDisconnect(function(reason)
    client:_handleDisconnect(reason)
  end)
  conn:onReceive(function(msg)
    if msg.type == 'accept-client' then
      client:_handleConnect(msg.clientId, msg.clientData, msg.state)
    elseif msg.type == 'reject-client' then
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
