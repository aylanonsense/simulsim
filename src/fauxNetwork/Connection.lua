-- Load dependencies
local TransportLayer = require 'src/fauxNetwork/TransportLayer'

local Connection = {}
function Connection:new(params)
  local conn = {
    -- Private config vars
    _isClient = params and params.isClient or false,
    _sendTransportLayer = params and params.sendTransportLayer,
    _receiveTransportLayer = params and params.receiveTransportLayer,

    -- Private vars
    _status = 'disconnected',
    _bufferedMessages = {},
    _heldMessages = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _sendCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    connect = function(self)
      if self._status == 'disconnected' then
        self._status = 'connecting'
        self._sendTransportLayer:send({
          type = 'connect-request'
        }, true)
      end
    end,
    disconnect = function(self, reason)
      if self._status ~= 'disconnected' then
        local wasConnected = self:isConnected()
        self._status = 'disconnected'
        self._bufferedMessages = {}
        self._heldMessages = {}
        if wasConnected then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(reason or 'Manual disconnect')
          end
          self._sendTransportLayer:send({
            type = 'disconnected'
          }, true)
        end
      end
    end,
    isConnected = function(self)
      return self._status == 'connected'
    end,
    -- Sends a message immediately (alongside all buffered messages)
    send = function(self, msg)
      if self:isConnected() then
        self:buffer(msg)
        self:flush()
      end
    end,
    -- Buffers a message to be sent the next time flush is called
    buffer = function(self, msg)
      if self:isConnected() then
        table.insert(self._bufferedMessages, msg)
      end
    end,
    -- Sends all buffered messages that haven't been sent yet
    flush = function(self)
      if self:isConnected() then
        local messagesToSend = self._bufferedMessages
        self._bufferedMessages = {}
        -- Send the messages
        self._sendTransportLayer:send({
          type = 'messages',
          messages = messagesToSend
        })
        -- Trigger send callbacks
        for _, msg in ipairs(messagesToSend) do
          for _, callback in ipairs(self._sendCallbacks) do
            callback(msg)
          end
        end
      end
    end,

    -- Private methods
    _handleConnect = function(self)
      if self._status ~= 'connected' then
        self._status = 'connected'
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
        end
        -- Process the held messages
        local messagesToReceive = self._heldMessages
        self._heldMessages = {}
        for _, msg in ipairs(messagesToReceive) do
          self:_handleReceive(msg)
        end
      end
    end,
    _handleDisconnect = function(self, reason)
      if self._status ~= 'disconnected' then
        local wasConnected = self:isConnected()
        self._status = 'disconnected'
        self._bufferedMessages = {}
        self._heldMessages = {}
        if wasConnected then
          for _, callback in ipairs(self._disconnectCallbacks) do
            callback(reason or (self._isClient and 'Server forced disconnect' or 'Client disconnected'))
          end
        end
      end
    end,
    _handleReceive = function(self, msg)
      if self:isConnected() then
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

  -- Bind events
  conn._receiveTransportLayer:onReceive(function(packet)
    if packet.type == 'connect-request' and not conn._isClient then
      conn._sendTransportLayer:send({
        type = 'connect-accept'
      }, true)
    elseif packet.type == 'connect-accept' and conn._isClient and conn._status == 'connecting' then
      conn._sendTransportLayer:send({
        type = 'connected'
      }, true)
      conn:_handleConnect()
    elseif packet.type == 'connected' and not conn._isClient then
      conn:_handleConnect()
    elseif packet.type == 'disconnected' then
      conn:_handleDisconnect()
    elseif packet.type == 'messages' then
      for _, msg in ipairs(packet.messages) do
        conn:_handleReceive(msg)
      end
    end
  end)

  -- Return the new connection
  return conn
end

return Connection
