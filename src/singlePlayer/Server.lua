-- A client for the server to use
local Client = {}
function Client:new(clientId, conn)
  local client = {
    -- Public vars
    clientId = clientId,

    -- Private vars
    _conn = conn,
    _isConnected = true,
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    isConnected = function(self)
      return self._isConnected
    end,
    -- Forcefully disconnects the client from the server
    disconnect = function(self, reason)
      if self._isConnected then
        self._isConnected = false
        self._conn:disconnect()
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Server forced disconnect')
        end
      end
    end,
    buffer = function(self, msg)
      if self._isConnected then
        self._conn:buffer(msg)
      end
    end,
    flush = function(self)
      if self._isConnected then
        self._conn:flush()
      end
    end,
    send = function(self, msg)
      if self._isConnected then
        self._conn:send(msg)
      end
    end,

    -- Private methods
    _handleDisconnect = function(self, reason)
      if self._isConnected then
        self._isConnected = false
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason or 'Client disconnected')
        end
      end
    end,
    _handleReceive = function(self, msg)
      if self._isConnected then
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
    client:_handleReceive(msg)
  end)

  -- Return the new client
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
    buffer = function(self, clientId, msg)
      local client = self:getClientById(clientId)
      if client then
        client:buffer(msg)
      end
    end,
    -- Flushes all buffered messages to a client
    flush = function(self, clientId)
      local client = self:getClientById(clientId)
      if client then
        client:flush()
      end
    end,
    -- Sends a message (and all buffered messages) to a client
    send = function(self, clientId, msg)
      local client = self:getClientById(clientId)
      if client then
        client:send(msg)
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
    bufferAll = function(self, msg)
      self:forEachClient(function(client)
        client:buffer(msg)
      end)
    end,
    -- Flushes all buffered messages to all clients
    flushAll = function(self)
      self:forEachClient(function(client)
        client:flush()
      end)
    end,
    -- Sends a message (and all buffered messages) to al clients
    sendAll = function(self, msg)
      self:forEachClient(function(client)
        client:send(msg)
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
        local client = Client:new(clientId, conn)
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
      end
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
