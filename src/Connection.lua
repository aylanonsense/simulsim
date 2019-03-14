local Connection = {}

-- Creates a new Connection
function Connection:new()
  return {
    -- Private vars
    _isConnected = false,
    _messageBuffer = {},
    _heldMessages = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _sendCallbacks = {},
    _receiveCallbacks = {},

    -- Public API
    connect = function(self)
      if not self._isConnected then
        self._isConnected = true
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
        end
      end
    end,
    disconnect = function(self, reason)
      if self._isConnected then
        self._isConnected = false
        self._messageBuffer = {}
        self._heldMessages = {}
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(reason)
        end
      end
    end,
    isConnected = function(self)
      return self._isConnected
    end,
    -- Sends a message immediately (alongside all buffered messages)
    send = function(self, msg)
      if self._isConnected then
        self:buffer(msg)
        self:flush()
      end
    end,
    -- Buffers a message to be sent the next time flush is called
    buffer = function(self, msg)
      if self._isConnected then
        table.insert(self._messageBuffer, msg)
      end
    end,
    -- Sends all buffered messages that haven't been sent yet
    flush = function(self)
      if self._isConnected then
        local sentMessages = self._messageBuffer
        self._messageBuffer = {}
        -- Trigger onSend callback for each message sent
        for _, msg in ipairs(sentMessages) do
          for _, callback in ipairs(self._sendCallbacks) do
            callback(msg)
          end
        end
      end
    end,

    -- Private API
    _receive = function(self, msg)
      if self._isConnected then
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(msg)
        end
      else
        table.insert(self._heldMessages, msg)
      end
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onSend = function(self, callback)
      table.insert(self._sendCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end
  }
end

return Connection
