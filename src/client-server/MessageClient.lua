local MessageClient = {}

function MessageClient:new(params)
  params = params or {}
  local conn = params.conn
  local numConnectRetries = params.numConnectRetries or 8

  local client = {
    -- Private vars
    _status = 'disconnected',
    _numConnectRetries = numConnectRetries,
    _retriesLeft = 0,
    _timeSinceRetry = 0.00,
    _conn = conn,
    _handshake = nil,
    _bufferedMessages = {},
    _heldMessages = {},
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    connect = function(self, handshake)
      if self._status == 'disconnected' then
        self._status = 'connecting'
        self._retriesLeft = self._numConnectRetries
        self._timeSinceRetry = 0.00
        self._handshake = handshake
        -- Begin actually connecting
        self._conn:connect()
      end
    end,
    disconnect = function(self, reason)
      if self._status ~= 'disconnected' then
        local prevStatus = self._status
        self._status = 'disconnected'
        self._bufferedMessages = {}
        self._heldMessages = {}
        -- Disconnect from the server
        self._conn:send({ 'disconnect-request', reason })
        self._conn:disconnect()
        -- Trigger callbacks
        if prevStatus == 'connected' then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(reason or 'Connection terminated by client')
          end
        else
          for _, callback in ipairs(self._connectFailureCallbacks) do
            callback(reason or 'Connection terminated by client')
          end
        end
      end
    end,
    isConnected = function(self)
      return self._status == 'connected'
    end,
    isConnecting = function(self)
      return self._status == 'connecting' or self._status == 'handshaking'
    end,
    send = function(self, msg)
      self:buffer(msg)
      self:flush()
    end,
    buffer = function(self, msg)
      if self._status == 'connected' then
        table.insert(self._bufferedMessages, msg)
      end
    end,
    flush = function(self)
      if self._status == 'connected' and #self._bufferedMessages > 0 then
        local messages = self._bufferedMessages
        self._bufferedMessages = {}
        self._conn:send({ 'messages', messages })
      end
    end,
    update = function(self, dt)
      self._conn:update(dt)
      -- Retry connection request
      if self._status == 'handshaking' then
        self._timeSinceRetry = self._timeSinceRetry + dt
        if self._timeSinceRetry >= 1.000 then
          if self._retriesLeft <= 0 then
            self:disconnect('Could not connect after ' .. self._numConnectRetries .. ' retries')
          else
            self._retriesLeft = self._retriesLeft - 1
            self._timeSinceRetry = 0.00
            self._conn:send({ 'connect-request', self._handshake })
          end
        end
      end
    end,
    simulateNetworkConditions = function(self, params)
      self._conn:simulateNetworkConditions(params)
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
    end,

    -- Private methods
    _handleConnect = function(self)
      -- Ready to begin handshaking
      if self._status == 'connecting' then
        self._status = 'handshaking'
        self._retriesLeft = 5
        self._timeSinceRetry = 0.00
        self._conn:send({ 'connect-request', self._handshake })
      -- Otherwise if we shouldn't be connected, silently end the connection
      elseif self._status == 'disconnected' then
        self._conn:disconnect()
      end
    end,
    _handleDisconnect = function(self)
      -- If we were connected, trigger disconnect callbacks
      if self._status == 'connected' then
        self._status = 'disconnected'
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback('Connection terminated')
        end
      -- If we were connecting, then treat it as a connection failure
      elseif self._status == 'connecting' or self._status == 'handshaking' then
        self._status = 'disconnected'
        for _, callback in ipairs(self._connectFailureCallbacks) do
          callback('Could not connect to server')
        end
      end
    end,
    _handleReceive = function(self, messageType, messageContent)
      -- The client has accepted the connection request, we are now connected!
      if self._status == 'handshaking' and messageType == 'connect-accept' then
        self._status = 'connected'
        local messagesToReceive = self._heldMessages
        self._heldMessages = {}
        -- Trigger connect callbacks
        for _, callback in ipairs(self._connectCallbacks) do
          callback(messageContent)
        end
        -- Play back any held messages
        for _, msg in ipairs(messagesToReceive) do
          if self._status == 'connected' then
            for _, callback in ipairs(self._receiveCallbacks) do
              callback(msg)
            end
          end
        end
      -- The server has refused the client connection
      elseif self._status ~= 'disconnected' and messageType == 'force-disconnect' then
        local prevStatus = self._status
        self._status = 'disconnected'
        self._bufferedMessages = {}
        self._heldMessages = {}
        -- Trigger disconnect callbacks
        if prevStatus == 'connected' then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(messageContent or 'Connection terminated by server')
          end
        -- Trigger connect failure callbacks
        else
          for _, callback in ipairs(self._connectFailureCallbacks) do
            callback(messageContent or 'Rejected by server')
          end
        end
      -- The client received a message
      elseif self._status == 'connected' and messageType == 'messages' then
        for _, msg in ipairs(messageContent) do
          if self._status == 'connected' then
            for _, callback in ipairs(self._receiveCallbacks) do
              callback(msg)
            end
          end
        end
      -- The client received some messages too early, so hold onto em
      elseif self._status ~= 'disconnected' and messageType == 'messages' then
        for _, msg in ipairs(messageContent) do
          table.insert(self._heldMessages, msg)
        end
      end
    end
  }

  -- Bind events
  conn:onConnect(function()
    client:_handleConnect()
  end)
  conn:onDisconnect(function()
    client:_handleDisconnect()
  end)
  conn:onReceive(function(msg)
    client:_handleReceive(msg[1], msg[2])
  end)

  return client
end

return MessageClient
