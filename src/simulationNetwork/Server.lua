-- Load dependencies
local MessageServer = require 'src/network/MessageServer'
local SimulationRunner = require 'src/simulation/SimulationRunner'
local stringUtils = require 'src/utils/string'

local Client = {}
function Client:new(params)
  params = params or {}
  local server = params.server
  local clientId = params.clientId
  local connId = params.connId
  local framesBetweenFlushes = params.framesBetweenFlushes or 3
  local framesBetweenSnapshots = params.framesBetweenSnapshots or 25

  return {
    -- Private config vars
    _framesBetweenFlushes = framesBetweenFlushes,
    _framesBetweenSnapshots = framesBetweenSnapshots,

    -- Private vars
    _server = server,
    _messageServer = server._messageServer,
    _connId = connId,
    _framesUntilNextFlush = 0,
    _framesUntilNextSnapshot = 0,
    _disconnectCallbacks = {},

    -- Public vars
    clientId = clientId,
    data = {},

    -- Public methods
    -- Disconnect a client that's connected to the server
    disconnect = function(self, reason)
      self._messageServer:disconnect(self._connId, reason)
    end,
    -- Returns true if the client's connection has been accepted by the server
    isConnected = function(self)
      return self._messageServer:isConnected(self._connId)
    end,
    update = function(self, dt, df)
      -- Send a snapshot of the simulation state every so often
      if self._framesBetweenSnapshots > 0 then
        self._framesUntilNextSnapshot = self._framesUntilNextSnapshot - df
        if self._framesUntilNextSnapshot <= 0 then
          self._framesUntilNextSnapshot = self._framesBetweenSnapshots
          self:_sendStateSnapshot()
        end
      end
      -- Flush the client's messages every so often
      if self._framesBetweenFlushes > 0 then
        self._framesUntilNextFlush = self._framesUntilNextFlush - df
        if self._framesUntilNextFlush <= 0 then
          self._framesUntilNextFlush = self._framesBetweenFlushes
          self._messageServer:flush(self._connId)
        end
      end
    end,

    -- Private methods
    _handleDisconnect = function(self, reason)
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(reason)
      end
    end,
    _sendStateSnapshot = function(self)
      self._messageServer:buffer(self._connId, { 'state-snapshot', self._server:getSimulation():getState() })
    end,
    _sendPingResponse = function(self, pingResponse)
      self._messageServer:buffer(self._connId, { 'ping-response', pingResponse })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,
    _sendEvent = function(self, event, params)
      self._messageServer:buffer(self._connId, { 'event', event })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,
    -- Rejects an event that came from this client
    _rejectEvent = function(self, event)
      self._messageServer:buffer(self._connId, { 'reject-event', event })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,

    -- Callback methods
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end
  }
end

-- The server, which manages connected clients
local Server = {}
function Server:new(params)
  params = params or {}
  local listener = params.listener
  local initialState = params.initialState
  local simulationDefinition = params.simulationDefinition
  local maxClientEventFramesLate = params.maxClientEventFramesLate or 0
  local maxClientEventFramesEarly = params.maxClientEventFramesEarly or 45

  -- Create the simulation
  local simulation = simulationDefinition:new({
    initialState = initialState
  })
  local runner = SimulationRunner:new({
    simulation = simulation,
    framesOfHistory = maxClientEventFramesLate + 1
  })

  -- Wrap the listener in a message server to make it easier to work with
  local messageServer = MessageServer:new({
    listener = listener
  })

  local server = {
    -- Private config vars
    _maxClientEventFramesLate = maxClientEventFramesLate,
    _maxClientEventFramesEarly = maxClientEventFramesEarly,

    -- Private vars
    _messageServer = messageServer,
    _nextClientId = 1,
    _clients = {},
    _simulation = simulation,
    _runner = runner,
    _connectCallbacks = {},

    -- Public methods
    -- Starts the server listening for new client connections
    startListening = function(self)
      self._messageServer:startListening()
    end,
    -- Returns true if the server is listening for new client connections
    isListening = function(self)
      return self._messageServer:isListening()
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
    getSimulation = function(self)
      return self._simulation
    end,
    update = function(self, dt, df)
      -- Update the underlying messaging server
      self._messageServer:update(dt)
      -- Update the simulation via the simulation runner
      df = self._runner:update(dt, df)
      -- Update all clients
      for _, client in ipairs(self._clients) do
        client:update(dt, df)
      end
      -- Return the number of frames that have been advanced
      return df
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
    _getClientByConnId = function(self, connId)
      for i = 1, #self._clients do
        if self._clients[i]._connId == connId then
          return self._clients[i], i
        end
      end
    end,
    _addServerMetadata = function(self, obj)
      obj.serverMetadata = {
        frameReceived = self._simulation.frame
      }
      return obj
    end,
    _handleConnectRequest = function(self, connId, handshake, accept, reject)
      -- Create a new client
      local clientId = self._nextClientId
      self._nextClientId = self._nextClientId + 1
      local client = Client:new({
        server = self,
        clientId = clientId,
        connId = connId
      })
      local accept2 = function(clientData)
        -- Insert the client into the list of clients
        table.insert(self._clients, client)
        -- Accept the connection
        accept({ clientId, clientData or {}, self._simulation:getState() })
        -- Trigger connect callbacks
        for _, callback in ipairs(self._connectCallbacks) do
          callback(client)
        end
      end
      self:handleConnectRequest(client, handshake, accept2, reject)
    end,
    _handleDisconnect = function(self, connId, reason)
      local client, i = self:_getClientByConnId(connId)
      if client then
        -- Remove the client
        table.remove(self._clients, i)
        -- Trigger the client's disconnect callbacks
        client:_handleDisconnect(reason or 'Connection terminated')
      end
    end,
    _handleReceive = function(self, connId, messageType, messageContent)
      local client = self:_getClientByConnId(connId)
      if client then
        if messageType == 'event' then
          -- Add some metadata onto the event recording the fact that it was received
          local event = self:_addServerMetadata(messageContent)
          -- TODO reject if too far in the past
          -- TODO update frame if in the past and adjusting is allowed
          local eventApplied = false
          if self._simulation.frame - self._maxClientEventFramesLate < event.frame and event.frame <= self._simulation.frame + 1 + self._maxClientEventFramesEarly and self:shouldAcceptEventFromClient(client, event) then
            -- Apply the event server-side and let all clients know about it
            eventApplied = self:_applyEvent(event)
          end
          if not eventApplied then
            -- Let the client know that their event was rejected or wasn't able to be applied
            client:_rejectEvent(event)
          end
        elseif messageType == 'ping' then
          local pingResponse = self:_addServerMetadata(messageContent)
          pingResponse.frame = self._simulation.frame
          client:_sendPingResponse(pingResponse)
        end
      end
    end,
    _applyEvent = function(self, event, params)
      -- Apply the event server-side
      if self._runner:applyEvent(event) then
        -- Let all clients know about the event
        for _, client in ipairs(self._clients) do
          if self:shouldSendEventToClient(client, event) then
            client:_sendEvent(event)
          end
        end
        return true
      else
        return false
      end
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end
  }

  -- Bind events
  messageServer.handleConnectRequest = function(self, connId, handshake, accept, reject)
    server:_handleConnectRequest(connId, handshake, accept, reject)
  end
  messageServer:onDisconnect(function(connId, reason)
    server:_handleDisconnect(connId, reason)
  end)
  messageServer:onReceive(function(connId, msg)
    server:_handleReceive(connId, msg[1], msg[2])
  end)

  return server
end

return Server
