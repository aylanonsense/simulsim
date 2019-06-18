local tableUtils = require 'src/utils/table'

local MessageServer = {}

function MessageServer:new(params)
  params = params or {}
  local listener = params.listener

  local server = {
    -- Private vars
    _listener = listener,
    _connections = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},
    _reusedSendObject = {},

    -- Public methods
    startListening = function(self)
      self._listener:startListening()
    end,
    isListening = function(self)
      return self._listener:isListening()
    end,
    disconnect = function(self, connId, reason)
      local conn = self._connections[connId]
      self._connections[connId] = nil
      if conn and conn.status ~= 'disconnected' then
        local prevStatus = conn.status
        conn.status = 'disconnected'
        tableUtils.clearProps(conn.heldMessages)
        tableUtils.clearProps(conn.bufferedMessages)
        -- Forcefully disconnect the connection
        self:_send(connId, 'force-disconnect', reason)
        self._listener:disconnect(connId)
        -- Trigger disconnect callbacks
        if prevStatus == 'connected' then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(connId, reason or 'Connection terminated by server')
          end
        end
      end
    end,
    isConnected = function(self, connId)
      return self._connections[connId] and self._connections[connId].status == 'connected'
    end,
    send = function(self, connId, msg)
      self:buffer(connId, msg)
      self:flush(connId)
    end,
    buffer = function(self, connId, msg)
      local conn = self._connections[connId]
      if conn and conn.status == 'connected' then
        table.insert(conn.bufferedMessages, msg)
      end
    end,
    flush = function(self, connId)
      local conn = self._connections[connId]
      if conn and conn.status == 'connected' and #conn.bufferedMessages > 0 then
        self:_send(connId, 'messages', conn.bufferedMessages)
        tableUtils.clearProps(conn.bufferedMessages)
      end
    end,
    update = function(self, dt)
      self._listener:update(dt)
    end,
    handleConnectRequest = function(self, connId, handshake, accept, reject)
      accept()
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
    end,

    -- Private methods
    _send = function(self, connId, messageType, messageContent)
      self._reusedSendObject[1] = messageType
      self._reusedSendObject[2] = messageContent
      self._listener:send(connId, self._reusedSendObject)
    end,
    _handleDisconnect = function(self, connId)
      local conn = self._connections[connId]
      self._connections[connId] = nil
      if conn and conn.status == 'connected' then
        conn.status = 'disconnected'
        tableUtils.clearProps(conn.heldMessages)
        tableUtils.clearProps(conn.bufferedMessages)
        -- Trigger disconnect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(connId, 'Connection terminated')
        end
      end
    end,
    _handleReceive = function(self, connId, messageType, messageContent)
      if not self._connections[connId] then
        self._connections[connId] = {
          status = 'connecting',
          connectAcceptData = nil,
          heldMessages = {},
          bufferedMessages = {}
        }
      end
      local conn = self._connections[connId]
      -- The client wants to officially connect
      if conn.status == 'connecting' and messageType == 'connect-request' then
        -- Accept the client's request to connect
        local accept = function(data)
          conn.status = 'connected'
          self._connections[connId].connectAcceptData = data
          self:_send(connId, 'connect-accept', self._connections[connId].connectAcceptData)
          -- Trigger connect callbacks
          for _, callback in ipairs(self._connectCallbacks) do
            callback(connId, data)
          end
          -- Receive held messages
          for _, msg in ipairs(conn.heldMessages) do
            if conn.status == 'connected' then
              for _, callback in ipairs(self._receiveCallbacks) do
                callback(connId, msg)
              end
            end
          end
          tableUtils.clearProps(conn.heldMessages)
        end
        -- Reject the client's request to connect
        local reject = function(reason)
          conn.status = 'disconnected'
          tableutils.clearProps(conn.heldMessages)
          tableutils.clearProps(conn.bufferedMessages)
          self._connections[connId] = nil
          self:_send(connId, 'force-disconnect', reason)
          self._listener:disconnect(connId)
        end
        -- Determine if the connection request should be accepted or rejected
        if self._listener:isListening() then
          self:handleConnectRequest(connId, messageContent, accept, reject)
        else
          reject('Server not running')
        end
      -- The client didn't get the memo that they're already connected
      elseif conn.status == 'connected' and messageType == 'connect-request' then
        self:_send(connId, 'connect-accept', self._connections[connId].connectAcceptData)
      -- The client is disconnecting
      elseif conn.status ~= 'disconnected' and messageType == 'disconnect-request' then
        local prevStatus = conn.status
        conn.status = 'disconnected'
        tableUtils.clearProps(conn.heldMessages)
        tableUtils.clearProps(conn.bufferedMessages)
        -- Trigger disconnect callbacks
        if prevStatus == 'connected' then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(connId, messageContent or 'Connection terminated by client')
          end
        end
      -- The server received a message
      elseif conn.status == 'connected' and messageType == 'messages' then
        for _, msg in ipairs(messageContent) do
          if conn.status == 'connected' then
            for _, callback in ipairs(self._receiveCallbacks) do
              callback(connId, msg)
            end
          end
        end
      -- The server received a message to early, so hold onto em
      elseif conn.status ~= 'disconnected' and messageType == 'messages' then
        for _, msg in messageContent do
          table.insert(conn.heldMessages, msg)
        end
      end
    end
  }

  -- Bind events
  listener:onDisconnect(function(connId)
    server:_handleDisconnect(connId)
  end)
  listener:onReceive(function(connId, msg)
    server:_handleReceive(connId, msg[1], msg[2])
  end)

  return server
end

return MessageServer
