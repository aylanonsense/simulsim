local tableUtils = require 'src/utils/table'
local constants = require 'src/client-server/messageConstants'

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
        for i = #conn.bufferedMessages, 2, -1 do
          conn.bufferedMessages[i] = nil
        end
        tableUtils.clearProps(conn.heldMessages)
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
    send = function(self, connId, messageType, messageContent)
      self:buffer(connId, messageType, messageContent)
      self:flush(connId)
    end,
    buffer = function(self, connId, messageType, messageContent)
      local conn = self._connections[connId]
      if conn and conn.status == 'connected' then
        table.insert(conn.bufferedMessages, messageType)
        table.insert(conn.bufferedMessages, messageContent)
      end
    end,
    flush = function(self, connId)
      local conn = self._connections[connId]
      if conn and conn.status == 'connected' and #conn.bufferedMessages > 0 then
        self._listener:send(connId, conn.bufferedMessages)
        for i = #conn.bufferedMessages, 2, -1 do
          conn.bufferedMessages[i] = nil
        end
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
        for i = #conn.bufferedMessages, 2, -1 do
          conn.bufferedMessages[i] = nil
        end
        tableUtils.clearProps(conn.heldMessages)
        -- Trigger disconnect callbacks
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback(connId, 'Connection terminated')
        end
      end
    end,
    _handleReceive = function(self, connId, message)
      if not self._connections[connId] then
        self._connections[connId] = {
          status = 'connecting',
          connectAcceptData = nil,
          heldMessages = {},
          bufferedMessages = { constants.MESSAGES }
        }
      end
      local conn = self._connections[connId]
      local messageType = message[1]
      -- The client wants to officially connect
      if conn.status == 'connecting' and messageType == constants.CONNECT_REQUEST then
        -- Accept the client's request to connect
        local accept = function(data)
          conn.status = 'connected'
          self._connections[connId].connectAcceptData = data
          self:_send(connId, constants.CONNECT_ACCEPT, self._connections[connId].connectAcceptData)
          -- Trigger connect callbacks
          for _, callback in ipairs(self._connectCallbacks) do
            callback(connId, data)
          end
          -- Receive held messages
          for i = 1, #conn.heldMessages, 2 do
            if conn.status == 'connected' then
              for _, callback in ipairs(self._receiveCallbacks) do
                callback(connId, conn.heldMessages[i], conn.heldMessages[i + 1])
              end
            end
          end
          tableUtils.clearProps(conn.heldMessages)
        end
        -- Reject the client's request to connect
        local reject = function(reason)
          conn.status = 'disconnected'
          for i = #conn.bufferedMessages, 2, -1 do
            conn.bufferedMessages[i] = nil
          end
          tableutils.clearProps(conn.heldMessages)
          self._connections[connId] = nil
          self:_send(connId, constants.FORCE_DISCONNECT, reason)
          self._listener:disconnect(connId)
        end
        -- Determine if the connection request should be accepted or rejected
        if self._listener:isListening() then
          self:handleConnectRequest(connId, message[2], accept, reject)
        else
          reject('Server not running')
        end
      -- The client didn't get the memo that they're already connected
      elseif conn.status == 'connected' and messageType == constants.CONNECT_REQUEST then
        self:_send(connId, constants.CONNECT_ACCEPT, self._connections[connId].connectAcceptData)
      -- The client is disconnecting
      elseif conn.status ~= 'disconnected' and messageType == constants.DISCONNECT_REQUEST then
        local prevStatus = conn.status
        conn.status = 'disconnected'
        for i = #conn.bufferedMessages, 2, -1 do
          conn.bufferedMessages[i] = nil
        end
        tableUtils.clearProps(conn.heldMessages)
        -- Trigger disconnect callbacks
        if prevStatus == 'connected' then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(connId, message[2] or 'Connection terminated by client')
          end
        end
      -- The server received a message
      elseif conn.status == 'connected' and messageType == constants.MESSAGES then
        for i = 2, #message, 2 do
          if conn.status == 'connected' then
            for _, callback in ipairs(self._receiveCallbacks) do
              callback(connId, message[i], message[i + 1])
            end
          end
        end
      -- The server received a message to early, so hold onto em
      elseif conn.status ~= 'disconnected' and messageType == constants.MESSAGES then
        for i = 2, #message do
          table.insert(conn.heldMessages, message[i])
        end
      end
    end
  }

  -- Bind events
  listener:onDisconnect(function(connId)
    server:_handleDisconnect(connId)
  end)
  listener:onReceive(function(connId, msg)
    server:_handleReceive(connId, msg)
  end)

  return server
end

return MessageServer
