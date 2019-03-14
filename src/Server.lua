-- A client for the server to use
local Client = {}
function Client:new(clientId, conn)
  -- Create a new client
  local client = {
    -- Public vars
    clientId = clientId,

    -- Private vars
    _conn = conn,
    _isConnected = true,
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public API
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
      self._conn:buffer(msg)
    end,
    flush = function(self)
      self._conn:flush()
    end,
    send = function(self, msg)
      self._conn:send(msg)
    end,

    -- Private API
    _receive = function(self, msg)
      self:onReceive(msg)
    end,

    -- Callback methods
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end
  }
  -- Bind connection event handlers to the client
  conn:onDisconnect(function(reason)
    if client._isConnected then
      client._isConnected = false
      for _, callback in ipairs(client._disconnectCallbacks) do
        callback(reason or 'Client disconnected')
      end
    end
  end)
  conn:onReceive(function(msg)
    for _, callback in ipairs(client._receiveCallbacks) do
      callback(msg)
    end
  end)
  -- Return the new client
  return client
end

-- The server, which manages connected clients
local Server = {}
function Server:new()
  return {
    -- Private vars
    _nextClientId = 1,
    _clients = {},
    _startCallbacks = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public API
    -- Starts the server listening for client connections
    start = function(self)
      for _, callback in ipairs(self._startCallbacks) do
        callback()
      end
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

    -- Private API
    -- Connects a client to the server
    _connect = function(self, conn)
      -- Create a new client
      local clientId = self._nextClientId
      self._nextClientId = self._nextClientId + 1
      local client = Client:new(clientId, conn)
      -- Add the new client to the server
      table.insert(self._clients, client)
      -- Bind events
      client:onDisconnect(function(reason)
        for i = 1, #self._clients do
          if self._clients[i].clientId == client.clientId then
            table.remove(self._clients, i)
            break
          end
        end
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(client, reason or 'Server forced disconnect')
        end
      end)
      client:onReceive(function(msg)
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(client, msg)
        end
      end)
      -- Trigger the connect callback
      for _, callback in ipairs(self._connectCallbacks) do
        callback(client)
      end
    end,

    -- Callback methods
    onStart = function(self, callback)
      table.insert(self._startCallbacks, callback)
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
