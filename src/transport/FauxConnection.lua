-- Load dependencies
local TransportLayer = require 'src/transport/FauxTransportLayer'

local Connection = {}
function Connection:new(params)
  local isClient = params and params.isClient or false
  local sendTransportLayer = params and params.sendTransportLayer
  local receiveTransportLayer = params and params.receiveTransportLayer

  local conn = {
    -- Private config vars
    _isClient = isClient,
    _sendTransportLayer = sendTransportLayer,
    _receiveTransportLayer = receiveTransportLayer,

    -- Private vars
    _status = 'disconnected',
    _flushReliably = false,
    _bufferedMessages = {},
    _heldMessages = {},
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _sendCallbacks = {},
    _flushCallbacks = {},
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
        local wasConnected = self._status == 'connected'
        self._status = 'disconnected'
        self._flushReliably = false
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
    send = function(self, msg, reliable)
      if self._status == 'connected' then
        self:buffer(msg)
        self:flush(reliable)
      end
    end,
    -- Buffers a message to be sent the next time flush is called
    buffer = function(self, msg, reliable)
      if self._status == 'connected' then
        if reliable then
          self._flushReliably = true
        end
        table.insert(self._bufferedMessages, msg)
      end
    end,
    -- Sends all buffered messages that haven't been sent yet
    flush = function(self, reliable)
      if self._status == 'connected' and #self._bufferedMessages > 0 then
        for _, callback in ipairs(self._flushCallbacks) do
          callback(messagesToSend)
        end
        local messagesToSend = self._bufferedMessages
        self._bufferedMessages = {}
        for _, message in ipairs(messagesToSend) do
          for _, callback in ipairs(self._sendCallbacks) do
            callback(message)
          end
        end
        -- Send the messages
        self._sendTransportLayer:send({
          type = 'messages',
          messages = messagesToSend
        }, reliable or self._flushReliably)
        self._flushReliably = false
      end
    end,
    -- Returns the total roundtrip time for messages in milliseconds
    getLatency = function(self)
      -- Cheating! Implement some proper pinging please
      return self._sendTransportLayer._latency + self._sendTransportLayer._latencyDeviation +
        self._receiveTransportLayer._latency + self._receiveTransportLayer._latencyDeviation
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
        local wasConnected = self._status == 'connected'
        self._status = 'disconnected'
        self._flushReliably = false
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
      if self._status ~= 'disconnected' then
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
    onFlush = function(self, callback)
      table.insert(self._flushCallbacks, callback)
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
