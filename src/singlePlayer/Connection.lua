-- Load dependencies
local TransportLayer = require 'src/singlePlayer/TransportLayer'

local Connection = {}
function Connection:new(params)
  params = params or {}

  -- Config params
  local isClient = params.isClient or false
  local sendTransportLayer = params.sendTransportLayer
  local receiveTransportLayer = params.receiveTransportLayer

  -- Private vars
  local status = 'disconnected'
  local bufferedMessages = {}
  local heldMessages = {}
  local connectCallbacks = {}
  local disconnectCallbacks = {}
  local sendCallbacks = {}
  local receiveCallbacks = {}

  -- Private API
  local connect, disconnect, receive
  connect = function(self)
    if status ~= 'connected' then
      status = 'connected'
      for _, callback in ipairs(connectCallbacks) do
        callback()
      end
      -- Process the held messages
      local messagesToReceive = heldMessages
      heldMessages = {}
      for _, msg in ipairs(messagesToReceive) do
        receive(self, msg)
      end
    end
  end
  disconnect = function(self, reason)
    if status ~= 'disconnected' then
      local wasConnected = self:isConnected()
      status = 'disconnected'
      bufferedMessages = {}
      heldMessages = {}
      if wasConnected then
        for _, callback in ipairs(disconnectCallbacks) do
          callback(reason or (isClient and 'Server forced disconnect' or 'Client disconnected'))
        end
      end
    end
  end
  receive = function(self, msg)
    if self:isConnected() then
      for _, callback in ipairs(receiveCallbacks) do
        callback(msg)
      end
    else
      table.insert(heldMessages, msg)
    end
  end

  -- Public API
  local connection = {
    connect = function(self)
      if status == 'disconnected' then
        status = 'connecting'
        sendTransportLayer:send({
          type = 'connect-request'
        }, true)
      end
    end,
    disconnect = function(self, reason)
      if status ~= 'disconnected' then
        local wasConnected = self:isConnected()
        status = 'disconnected'
        bufferedMessages = {}
        heldMessages = {}
        if wasConnected then
          for _, callback in ipairs(disconnectCallbacks) do
            callback(reason or 'Manual disconnect')
          end
          sendTransportLayer:send({
            type = 'disconnected'
          }, true)
        end
      end
    end,
    isConnected = function(self)
      return status == 'connected'
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
        table.insert(bufferedMessages, msg)
      end
    end,
    -- Sends all buffered messages that haven't been sent yet
    flush = function(self)
      if self:isConnected() then
        local messagesToSend = bufferedMessages
        bufferedMessages = {}
        -- Send the messages
        sendTransportLayer:send({
          type = 'messages',
          messages = messagesToSend
        })
        -- Trigger send callbacks
        for _, msg in ipairs(messagesToSend) do
          for _, callback in ipairs(sendCallbacks) do
            callback(msg)
          end
        end
      end
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(connectCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(disconnectCallbacks, callback)
    end,
    onSend = function(self, callback)
      table.insert(sendCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(receiveCallbacks, callback)
    end
  }

  -- Bind events
  receiveTransportLayer:onReceive(function(msg)
    if msg.type == 'connect-request' then
      sendTransportLayer:send({
        type = 'connect-accept'
      }, true)
    elseif msg.type == 'connect-accept' then
      sendTransportLayer:send({
        type = 'connected'
      }, true)
      connect(connection)
    elseif msg.type == 'connected' then
      connect(connection)
    elseif msg.type == 'disconnected' then
      disconnect(connection)
    elseif msg.type == 'messages' then
      for _, msg2 in ipairs(msg.messages) do
        receive(connection, msg2)
      end
    end
  end)

  -- Return the new connection
  return connection
end

-- Creates a pair of connections with transport layers between them
function Connection:createConnectionPair(params)
  -- Create transport layers
  local clientToServer = TransportLayer:new(params)
  local serverToClient = TransportLayer:new(params)

  -- Create connections
  local clientConn = Connection:new({
    isClient = true,
    sendTransportLayer = clientToServer,
    receiveTransportLayer = serverToClient
  })
  local serverConn = Connection:new({
    isClient = false,
    sendTransportLayer = serverToClient,
    receiveTransportLayer = clientToServer
  })

  -- Return connections
  return clientConn, serverConn
end

return Connection
