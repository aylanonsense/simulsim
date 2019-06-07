-- Load dependencies
local LocalConnection = require 'src/transport/LocalConnection'
local LocalConnectionListener = require 'src/transport/LocalConnectionListener'
local LocalTransportStream = require 'src/transport/LocalTransportStream'
local MessageClient = require 'src/client-server/MessageClient'
local MessageServer = require 'src/client-server/MessageServer'

describe('Message network', function()
  -- Randomize the order of the test cases
  randomize()

  -- Keep track of network vars
  local server, clients, streams
  after_each(function()
    server, clients, streams = nil, nil, nil
  end)

  -- Helper function to create a message network
  local function setUpNetwork(params)
    params = params or {}
    local latency = params.latency or 0
    local numClients = params.numClients or 1

    -- Keep track of transport streams
    streams = {}

    -- Create the server
    local listener = LocalConnectionListener:new()
    server = MessageServer:new({ listener = listener })

    -- Create the clients
    clients = {}
    for i = 1, numClients do
      -- Create the transport Streams
      local clientToServer = LocalTransportStream:new({ latency = latency })
      local serverToClient = LocalTransportStream:new({ latency = latency })
      table.insert(streams, clientToServer)
      table.insert(streams, serverToClient)

      -- Create the server connection
      local serverConn = LocalConnection:new({
        isClient = false,
        sendStream = serverToClient,
        receiveStream = clientToServer
      })
      serverConn:onConnect(function()
        listener:handleConnect(serverConn)
      end)

      -- Create the client
      local clientConn = LocalConnection:new({
        isClient = true,
        sendStream = clientToServer,
        receiveStream = serverToClient
      })
      local client = MessageClient:new({ conn = clientConn })
      table.insert(clients, client)
    end
  end

  -- Helper function that pretends time has passed
  local function progressTime(seconds)
    while seconds > 0 do
      local dt = math.min(seconds, 1 / 60)
      seconds = seconds - 1 / 60
      for _, stream in ipairs(streams) do
        stream:update(dt)
      end
      for _, client in ipairs(clients) do
        client:update(dt)
      end
      server:update(dt)
    end
  end

  describe('without latency', function()
    it('the client can send messages to the server', function()
      setUpNetwork({ latency = 0 })
      local receivedMessage = nil
      server:onReceive(function(connId, message) receivedMessage = message end)
      server:startListening()
      clients[1]:connect()
      assert.falsy(receivedMessage)
      clients[1]:send('hello')
      assert.equal(receivedMessage, 'hello')
    end)

    it('the server can send messages to its clients', function()
      setUpNetwork({ latency = 0 })
      local receivedMessage = nil
      clients[1]:onReceive(function(message) receivedMessage = message end)
      server:startListening()
      clients[1]:connect()
      assert.falsy(receivedMessage)
      server:send(1, 'hello')
      assert.equal(receivedMessage, 'hello')
    end)
  end)

  describe('with added latency', function()
    it('the client can send messages to the server', function()
      setUpNetwork({ latency = 200 })
      local receivedMessage = nil
      server:onReceive(function(connId, message) receivedMessage = message end)
      server:startListening()
      clients[1]:connect()
      progressTime(1.000)
      clients[1]:send('hello')
      progressTime(0.190)
      assert.falsy(receivedMessage)
      progressTime(0.020)
      assert.equal(receivedMessage, 'hello')
    end)

    it('the server can send messages to its clients', function()
      setUpNetwork({ latency = 200 })
      local receivedMessage = nil
      clients[1]:onReceive(function(message) receivedMessage = message end)
      server:startListening()
      clients[1]:connect()
      progressTime(1.000)
      server:send(1, 'hello')
      progressTime(0.190)
      assert.falsy(receivedMessage)
      progressTime(0.020)
      assert.equal(receivedMessage, 'hello')
    end)
  end)
end)
