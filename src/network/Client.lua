local Client = {}
function Client:new(params)
  local conn = params and params.conn

  local client = {
    -- Private vars
    _conn = conn,
    _status = 'disconnected',
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

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
      if self._status == 'connected' then
        -- Let the client know why it's getting disconnected
        self._conn:send({
          type = 'client-disconnect',
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
    isConnected = function(self)
      return self._status == 'connected'
    end,
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
    flush = function(self, reliable)
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
    _handleConnect = function(self, clientId, clientData)
      if self._status == 'connecting' then
        self._status = 'connected'
        self.clientId = clientId
        self.data = clientData or {}
        -- Trigger connect callbacks
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
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
        -- Trigger connect failure callbacks
        for _, callback in ipairs(self._connectFailureCallbacks) do
          callback('Connection terminated')
        end
      end
    end,
    _handleConnectReject = function(self, reason)
      if self._status ~= 'disconnected' then
        self._status = 'disconnected'
        self.clientId = nil
        self.data = {}
        self._conn:disconnect()
        -- Trigger connect failure callbacks
        for _, callback in ipairs(self._connectFailureCallbacks) do
          callback(reason or 'Connect request failed')
        end
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
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onConnectFailure = function(self, callback)
      table.insert(self._connectFailureCallbacks, callback)
    end,
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
    if msg.type == 'accept-client' then
      client:_handleConnect(msg.clientId, msg.clientData)
    elseif msg.type == 'reject-client' then
      client:_handleConnectReject(msg.reason)
    elseif msg.type == 'message' then
      client:_handleReceive(msg.message)
    elseif msg.type == 'force-disconnect' then
      client:_handleDisconnect(msg.reason)
    end
  end)

  return client
end

return Client
