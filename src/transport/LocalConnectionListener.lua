local LocalConnectionListener = {}
function LocalConnectionListener:new()
  return {
    -- Private vars
    _isListening = false,
    _nextConnId = 1,
    _connections = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    startListening = function(self)
      self._isListening = true
    end,
    isListening = function(self)
      return self._isListening
    end,
    disconnect = function(self, connId)
      if self._connections[connId] then
        self._connections[connId]:disconnect()
      end
    end,
    isConnected = function(self, connId)
      return self._connections[connId]
    end,
    send = function(self, connId, msg)
      if self._connections[connId] then
        self._connections[connId]:send(msg)
      end
    end,
    update = function(self, dt)
      for _, conn in pairs(self._connections) do
        conn:update(dt)
      end
    end,

    -- Extra method to allow faux connections to be passed to the listener
    handleConnect = function(self, conn)
      local connId = self._nextConnId
      self._nextConnId = self._nextConnId + 1
      self._connections[connId] = conn
      -- Bind events
      conn:onDisconnect(function()
        self._connections[connId] = nil
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(connId)
        end
      end)
      conn:onReceive(function(msg)
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(connId, msg)
        end
      end)
      -- Trigger connect callbacks
      for _, callback in ipairs(self._connectCallbacks) do
        callback(connId)
      end
    end,

    -- Callback methods
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

return LocalConnectionListener
