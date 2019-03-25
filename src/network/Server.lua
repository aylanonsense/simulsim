local Client = {}
function Client:new(params)
  local clientId = params and params.clientId
  local conn = params and params.conn

  local client = {
    -- Private vars
    _conn = conn,
    _status = 'connecting',
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public vars
    clientId = clientId,

    -- Public methods
    -- Allow a client to connect to the server
    accept = function(self, clientData)
      if self._status == 'connecting' then
        self._status = 'connected'
        self._conn:buffer({
          type = 'accept-client',
          clientId = self.clientId,
          clientData = clientData
        }, true)
        return true
      end
      return false
    end,
    -- Prevent a client from connecting to the server
    reject = function(self, reason)
      if self._status == 'connecting' then
        -- Let the client know why it was rejected
        self._status = 'disconnected'
        self._conn:send({
          type = 'reject-client',
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
      return self._status == 'connecting'
    end,
    buffer = function(self, msg, reliable)
      if self._status == 'connected' then
        self._conn:buffer({
          type = 'message',
          message = msg
        }, reliable)
      end
    end,
    flush = function(self, msg, reliable)
      if self._status == 'connected' then
        self._conn:flush(reliable)
      end
    end,
    send = function(self, msg, reliable)
      if self._status == 'connected' then
        self._conn:send({
          type = 'message',
          message = msg
        }, reliable)
      end
    end,

    -- Private methods
    _handleDisconnect = function(self, reason)
      if self._status == 'connected' then
        self._status = 'disconnected'
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Connection terminated')
        end
      elseif self._status == 'connecting' then
        self._status = 'disconnected'
        -- Don't trigger disconnect callbacks, because the client wasn't considered to be "connected"
      end
    end,
    _handleClientDisconnectRequest = function(self, reason)
      if self._status == 'connected' then
        self._status = 'disconnected'
        self._conn:disconnect('Client disconnected')
        -- Trigger disconnect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Client disconnected')
        end
      elseif self._status == 'connecting' then
        self._status = 'disconnected'
        self._conn:disconnect('Client disconnected')
        -- Don't trigger disconnect callbacks, because the client wasn't considered to be "connected"
      end
    end,
    _handleReceive = function(self, msg)
      if self._status == 'connected' then
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(msg)
        end
      end
    end,

    -- Callback methods
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end
  }

  -- Bind events
  conn:onDisconnect(function(reason)
    client:_handleDisconnect(reason)
  end)
  conn:onReceive(function(msg)
    if msg.type == 'message' then
      client:_handleReceive(msg.message)
    elseif msg.type == 'client-disconnect' then
      client:_handleClientDisconnectRequest(msg.reason)
    end
  end)

  return client
end

-- The server, which manages connected clients
local Server = {}
function Server:new()
  return {
    -- Private vars
    _isListening = false,
    _nextClientId = 1,
    _clients = {},
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
    -- Buffers a message to a client
    buffer = function(self, clientId, msg, reliable)
      local client = self:getClientById(clientId)
      if client then
        client:buffer(msg, reliable)
      end
    end,
    -- Flushes all buffered messages to a client
    flush = function(self, clientId, reliable)
      local client = self:getClientById(clientId)
      if client then
        client:flush(reliable)
      end
    end,
    -- Sends a message (and all buffered messages) to a client
    send = function(self, clientId, msg, reliable)
      local client = self:getClientById(clientId)
      if client then
        client:send(msg, reliable)
      end
    end,
    -- Disconnects a client
    disconnect = function(self, clientId, reason)
      local client = self:getClientById(clientId)
      if client then
        client:disconnect(reason)
      end
    end,
    -- Buffers a message to all clients
    bufferAll = function(self, msg, reliable)
      self:forEachClient(function(client)
        client:buffer(msg, reliable)
      end)
    end,
    -- Flushes all buffered messages to all clients
    flushAll = function(self, reliable)
      self:forEachClient(function(client)
        client:flush(reliable)
      end)
    end,
    -- Sends a message (and all buffered messages) to al clients
    sendAll = function(self, msg, reliable)
      self:forEachClient(function(client)
        client:send(msg, reliable)
      end)
    end,
    -- Disconnects all clients
    disconnectAll = function(self, reason)
      self:forEachClient(function(client)
        client:disconnect(reason)
      end)
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
        -- What happens if the client gets accepted
        local acceptClient = function(clientData)
          -- Accept the connection
          if client:accept(clientData) then
            -- Add the new client to the server
            table.insert(self._clients, client)
            -- Bind events
            client:onDisconnect(function(reason)
              self:_handleDisconnect(client, reason)
            end)
            client:onReceive(function(msg)
              self:_handleReceive(client, msg)
            end)
            -- Trigger the connect callback
            for _, callback in ipairs(self._connectCallbacks) do
              callback(client)
            end
            -- Flush the connect message to the client
            client:flush()
          end
        end
        -- What happens if the client gets rejected
        local rejectClient = function(reason)
          client:reject(reason)
        end
        -- Determine if the client should get accepted or rejected
        self:handleClientConnectAttempt(client, acceptClient, rejectClient)
      end
    end,
    -- Call accept with client data you'd like to give to the client, or reject with a reason for rejection
    handleClientConnectAttempt = function(self, client, accept, reject)
      accept()
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
    _handleReceive = function(self, client, msg)
      for _, callback in ipairs(self._receiveCallbacks) do
        callback(client, msg)
      end
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
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end
  }
end

return Server
