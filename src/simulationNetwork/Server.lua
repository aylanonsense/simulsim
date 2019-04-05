-- Load dependencies
local SimulationRunner = require 'src/simulation/SimulationRunner'
local stringUtils = require 'src/utils/string'

local Client = {}
function Client:new(params)
  params = params or {}
  local clientId = params.clientId
  local conn = params.conn

  local client = {
    -- Private vars
    _conn = conn,
    _status = 'handshaking',
    _connectRequestCallbacks = {},
    _disconnectCallbacks = {},
    _receiveEventCallbacks = {},

    -- Public vars
    clientId = clientId,
    data = {},
    framesBetweenFlushes = 0,
    framesUntilNextFlush = 0,

    -- Public methods
    -- Allow a client to connect to the server
    acceptConnection = function(self, handshake, clientData, state)
      if self._status == 'handshaking' then
        self._status = 'connected'
        self.data = clientData
        if handshake and handshake.framesBetweenFlushes then
          self.framesBetweenFlushes = handshake.framesBetweenFlushes
        end
        self._conn:buffer({
          type = 'connect-accept',
          clientId = self.clientId,
          clientData = clientData,
          state = state
        }, true)
        return true
      end
      return false
    end,
    -- Prevent a client from connecting to the server
    rejectConnection = function(self, reason)
      if self._status == 'handshaking' then
        -- Let the client know why it was rejected
        self._status = 'disconnected'
        self._conn:send({
          type = 'connect-reject',
          reason = reason
        }, true)
        self._conn:disconnect('Connection rejected')
        -- No need to trigger disconnect callbacks, the client wasn't "connected" as far as the server is concerned
      end
    end,
    -- Disconnect a client that's connected to the server
    disconnect = function(self, reason)
      if self._status == 'connected' then
        -- Let the client know why it's getting disconnected
        self._conn:send({
          type = 'force-disconnect',
          reason = reason
        }, true)
        self._status = 'disconnected'
        self._conn:disconnect('Manual disconnect')
        -- Trigger disconnect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Manual disconnect')
        end
      end
    end,
    -- Returns true if the client's connection has been accepted by the server
    isConnected = function(self)
      return self._status == 'connected'
    end,
    -- Returns true if the client is currently waiting to be accepted by the server
    isConnecting = function(self)
      return self._status == 'handshaking'
    end,
    sendEvent = function(self, event, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        self._conn:buffer({
          type = 'event',
          event = event
        }, reliable)
        if self.framesBetweenFlushes == 0 then
          self:flush()
        end
      end
    end,
    -- Rejects an event that came from this client
    rejectEvent = function(self, event, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        self._conn:buffer({
          type = 'reject-event',
          event = event
        }, reliable)
        if self.framesBetweenFlushes == 0 then
          self:flush()
        end
      end
    end,
    flush = function(self, params)
      local reliable = params and params.reliable
      if self._status == 'connected' then
        self._conn:flush(reliable)
      end
    end,
    update = function(self, dt, numFrames)
      -- Flush the client's messages every so often
      self.framesUntilNextFlush = self.framesUntilNextFlush - numFrames
      if self.framesUntilNextFlush <= 0 then
        self.framesUntilNextFlush = self.framesBetweenFlushes
        self:flush()
      end
    end,

    -- Private methods
    _handleClientConnectRequest = function(self, handshake)
      if self._status == 'handshaking' then
        for _, callback in ipairs(self._connectRequestCallbacks) do
          callback(handshake)
        end
      end
    end,
    _handleDisconnect = function(self, reason)
      local wasConnected = self._status == 'connected'
      if self._status ~= 'disconnected' then
        self._status = 'disconnected'
        if wasConnected then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(reason or 'Connection terminated')
          end
        end
      end
    end,
    _handleClientDisconnectRequest = function(self, reason)
      local wasConnected = self._status == 'connected'
      if self._status ~= 'disconnected' then
        self._status = 'disconnected'
        self._conn:disconnect('Client disconnected')
        -- Trigger disconnect callbacks
        if wasConnected then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(reason or 'Client disconnected')
          end
        end
      end
    end,
    _handleReceiveEvent = function(self, event)
      if self._status == 'connected' then
        for _, callback in ipairs(self._receiveEventCallbacks) do
          callback(event)
        end
      end
    end,

    -- Callback methods
    onConnectRequest = function(self, callback)
      table.insert(self._connectRequestCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onReceiveEvent = function(self, callback)
      table.insert(self._receiveEventCallbacks, callback)
    end,
  }

  -- Bind events
  conn:onDisconnect(function(reason)
    client:_handleDisconnect(reason)
  end)
  conn:onReceive(function(msg)
    if msg.type == 'connect-request' then
      client:_handleClientConnectRequest(msg.handshake)
    elseif msg.type == 'disconnect-request' then
      client:_handleClientDisconnectRequest(msg.reason)
    elseif msg.type == 'event' then
      client:_handleReceiveEvent(msg.event)
    end
  end)

  return client
end

-- The server, which manages connected clients
local Server = {}
function Server:new(params)
  params = params or {}
  local initialState = params.initialState
  local simulationDefinition = params.simulationDefinition

  -- Create the simulation
  local simulation = simulationDefinition:new({
    initialState = initialState
  })
  local runner = SimulationRunner:new({
    simulation = simulation
  })

  return {
    -- Private vars
    _isListening = false,
    _nextClientId = 1,
    _clients = {},
    _simulation = simulation,
    _runner = runner,
    _startListeningCallbacks = {},
    _stopListeningCallbacks = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    -- Starts the server listening for new client connections
    startListening = function(self)
      if not self._isListening then
        self._isListening = true
        for _, callback in ipairs(self._startListeningCallbacks) do
          callback()
        end
      end
    end,
    -- Stops the server listening for new client connections
    stopListening = function(self)
      if self._isListening then
        self._isListening = false
        for _, callback in ipairs(self._stopListeningCallbacks) do
          callback()
        end
      end
    end,
    -- Returns true if the server is listening for new client connections
    isListening = function(self)
      return self._isListening
    end,
    -- Gets a client with the given id
    getClientById = function(self, clientId)
      for _, client in ipairs(self._clients) do
        if client.clientId == clientId then
          return client
        end
      end
    end,
    -- Gets the clients that are currently connected to the server
    getClients = function(self)
      return self._clients
    end,
    -- Calls the callback function for each connected client
    forEachClient = function(self, callback)
      for i = #self._clients, 1, -1 do
        callback(self._clients[i])
      end
    end,
    -- Disconnects a client
    disconnect = function(self, clientId, reason)
      local client = self:getClientById(clientId)
      if client then
        client:disconnect(reason)
      end
    end,
    -- Disconnects all clients
    disconnectAll = function(self, reason)
      self:forEachClient(function(client)
        client:disconnect(reason)
      end)
    end,
    -- Fires an event for the simulation and lets all clients know
    fireEvent = function(self, eventType, eventData, params)
      -- Create an event
      local event = {
        id = 'server-' .. stringUtils.generateRandomString(10),
        frame = self._simulation.frame + 1,
        type = eventType,
        data = eventData
      }
      -- Apply the event server-side and let the clients know about it
      self:_applyEvent(event, params)
      -- Return the event
      return event
    end,
    -- Connects a client to the server
    handleConnect = function(self, conn)
      if self._isListening then
        -- Create a new client
        local clientId = self._nextClientId
        self._nextClientId = self._nextClientId + 1
        local client = Client:new({
          clientId = clientId,
          conn = conn
        })
        client:onConnectRequest(function(handshake)
          -- What happens if the client gets accepted
          local accept = function(clientData)
            -- Accept the connection
            if client:acceptConnection(handshake, clientData, self._simulation:getState()) then
              -- Add the new client to the server
              table.insert(self._clients, client)
              -- Bind events
              client:onDisconnect(function(reason)
                self:_handleDisconnect(client, reason)
              end)
              client:onReceiveEvent(function(event)
                self:_handleReceiveEvent(client, event)
              end)
              -- Trigger the connect callback
              for _, callback in ipairs(self._connectCallbacks) do
                callback(client)
              end
              -- Flush the connect message to the client
              client:flush()
            else
              client:rejectConnection('Failed to accept connection')
            end
          end
          -- What happens if the client gets rejected
          local reject = function(reason)
            client:rejectConnection(reason)
          end
          -- Determine if the client should get accepted or rejected
          self:handleConnectRequest(client, handshake, accept, reject)
        end)
      end
    end,
    getSimulation = function(self)
      return self._simulation
    end,
    update = function(self, dt)
      -- Update the simulation (via the simulation runner)
      local numFrames = self._runner:update(dt)
      -- Update all clients
      for _, client in ipairs(self._clients) do
        client:update(dt, numFrames)
      end
    end,

    -- Overridable methods
    -- Call accept with client data you'd like to give to the client, or reject with a reason for rejection
    handleConnectRequest = function(self, client, handshake, accept, reject)
      accept()
    end,
    -- By default the server sends every event to all clients
    shouldSendEventToClient = function(self, client, event)
      return true
    end,
    -- By default the server is entirely trusting
    shouldAcceptEventFromClient = function(self, client, event)
      return true
    end,

    -- Private methods
    -- Creates a new client on the server
    _handleDisconnect = function(self, client, reason)
      for i = 1, #self._clients do
        if self._clients[i].clientId == client.clientId then
          table.remove(self._clients, i)
          break
        end
      end
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(client, reason or 'Server forced disconnect')
      end
    end,
    _handleReceiveEvent = function(self, client, event, params)
      -- Add some metadata onto the event recording the fact that it was received
      event.serverMetadata = {
        frameReceived = self._simulation.frame
      }
      local eventApplied = false
      -- TODO reject if too far in the past
      -- TODO update frame if in the past and adjusting is allowed
      if self:shouldAcceptEventFromClient(client, event) then
        -- Apply the event server-side and let all clients know about it
        eventApplied = self:_applyEvent(event)
      end
      if not eventApplied then
        -- Let the client know that their event was rejected or wasn't able to be applied
        client:rejectEvent(event, params)
      end
    end,
    _applyEvent = function(self, event, params)
      -- Apply the event server-side
      if self._runner:applyEvent(event) then
        -- Let all clients know about the event
        self:forEachClient(function(client)
          if self:shouldSendEventToClient(client, event) then
            client:sendEvent(event, params)
          end
        end)
        return true
      end
      return false
    end,

    -- Callback methods
    onStartListening = function(self, callback)
      table.insert(self._startListeningCallbacks, callback)
    end,
    onStopListening = function(self, callback)
      table.insert(self._stopListeningCallbacks, callback)
    end,
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end
  }
end

return Server
