-- Load dependencies
local createFauxSimulationNetwork = require 'src/simulationNetwork/createFauxSimulationNetwork'
local Simulation = require 'src/simulation/Simulation'

describe('faux simulation network', function()
  randomize()

  -- Define a simulation
  local simulationDefinition = Simulation:define({
    initialState = {
      data = {
        fruits = { 'apple' }
      }
    },
    handleEvent = function(self, event)
      if event.type == 'add-fruit' then
        table.insert(self.data.fruits, event.data.fruit)
      end
    end
  })

  -- Keep track of network vars
  local server, clients, transportLayers
  before_each(function()
    createNetwork()
  end)

  -- Helper function to create a new faux network
  function createNetwork(params)
    params = params or {}
    params.simulationDefinition = params.simulationDefinition or simulationDefinition
    server, clients, transportLayers = createFauxSimulationNetwork(params)
  end

  -- Helper functions to pretend time has passed (by updating 60 times per second)
  function progressFrames(frames)
    local dt = 1 / 60
    for i = 1, frames do
      for _, transportLayer in ipairs(transportLayers) do
        transportLayer:update(dt)
        server:update(dt)
        for _, client in ipairs(clients) do
          client:update(dt)
        end
      end
    end
  end
  function progressTime(seconds)
    local dt = 1 / 60
    for i = 1, 60 * seconds do
      for _, transportLayer in ipairs(transportLayers) do
        transportLayer:update(dt)
        server:update(dt)
        for _, client in ipairs(clients) do
          client:update(dt)
        end
      end
    end
  end

  describe('the server', function()
    it('isn\'t listening for connections until startListening() is called', function()
      assert.False(server:isListening())
      server:startListening()
      assert.True(server:isListening())
    end)
    it('stops listening for connections once stopListening() is called', function()
      server:startListening()
      assert.True(server:isListening())
      server:stopListening()
      assert.False(server:isListening())
    end)
    it('keeps track of connected clients and exposes them through getClients()', function()
      createNetwork({ numClients = 3 })
      server:startListening()
      assert.is.equal(0, #server:getClients())
      clients[1]:connect()
      assert.is.equal(1, #server:getClients())
      clients[2]:connect()
      assert.is.equal(2, #server:getClients())
      clients[3]:connect()
      assert.is.equal(3, #server:getClients())
      clients[3]:disconnect()
      assert.is.equal(2, #server:getClients())
      clients[1]:disconnect()
      assert.is.equal(1, #server:getClients())
      clients[2]:disconnect()
      assert.is.equal(0, #server:getClients())
    end)
    it('can set client data on a client when it connects', function()
      server.handleConnectRequest = function(self, client, handshake, accept, reject)
        accept({ color = 'red' })
      end
      server:startListening()
      clients[1]:connect()
      assert.is.same({ color = 'red' }, clients[1].data)
      assert.is.same({ color = 'red' }, server:getClients()[1].data)
    end)
    it('can reject clients that try to connect', function()
      server.handleConnectRequest = function(self, client, handshake, accept, reject)
        reject('Test rejection message')
      end
      server:startListening()
      clients[1]:connect()
      assert.False(clients[1]:isConnected())
      assert.is.equal(0, #server:getClients())
    end)
    it('disconnects all currently-connected clients when disconnectAll() is called', function()
      server:startListening()
      clients[1]:connect()
      assert.True(clients[1]:isConnected())
      assert.is.equal(1, #server:getClients())
      server:disconnectAll('disconnect reason')
      assert.False(clients[1]:isConnected())
      assert.is.equal(0, #server:getClients())
    end)
    it('applies the event to the server-side simulation when fireEvent() is called', function()
      server:fireEvent('add-fruit', { fruit = 'banana' })
      progressFrames(1)
      assert.is.same({ 'apple', 'banana' }, server:getSimulation().data.fruits)
    end)
    it('applies event sent from clients to the server-side simulation', function()
      server:startListening()
      clients[1]:connect()
      clients[1]:fireEvent('add-fruit', { fruit = 'lemon' })
      progressFrames(10)
      assert.is.same({ 'apple', 'lemon' }, server:getSimulation().data.fruits)
    end)
    it('triggers onStartListening() callbacks when the server starts listening for connections', function()
      local callbackTriggered = false
      server:onStartListening(function(client) callbackTriggered = true end)
      assert.False(callbackTriggered)
      server:startListening()
      assert.True(callbackTriggered)
    end)
    it('triggers onStopListening() callbacks when the server stops listening for connections', function()
      local callbackTriggered = false
      server:onStopListening(function(client) callbackTriggered = true end)
      server:startListening()
      assert.False(callbackTriggered)
      server:stopListening()
      assert.True(callbackTriggered)
    end)
    it('triggers onConnect() callbacks when a client connects', function()
      local callbackTriggered = false
      server:onConnect(function(client) callbackTriggered = true end)
      server:startListening()
      assert.False(callbackTriggered)
      clients[1]:connect()
      assert.True(callbackTriggered)
    end)
    it('triggers onDisconnect() callbacks when a client disconnects', function()
      local callbackTriggered = false
      server:onDisconnect(function(client, reason) callbackTriggered = true end)
      server:startListening()
      clients[1]:connect()
      assert.False(callbackTriggered)
      clients[1]:disconnect('Disconnect reason')
      assert.True(callbackTriggered)
    end)
  end)
  describe('the client', function()
    it('can connect() to a listening server', function()
      server:startListening()
      assert.False(clients[1]:isConnected())
      clients[1]:connect()
      assert.True(server:getClients()[1]:isConnected())
      assert.True(clients[1]:isConnected())
    end)
    it('is assigned a clientId from the server', function()
      server:startListening()
      clients[1]:connect()
      assert.is.truthy(clients[1].clientId)
    end)
    it('matches the state of the server after connecting', function()
      server:fireEvent('add-fruit', { fruit = 'banana' })
      progressFrames(1)
      server:startListening()
      clients[1]:connect()
      assert.is.same(server:getSimulation().data.fruits, clients[1]:getSimulation().data.fruits)
    end)
    it('triggers onConnect() callbacks when connecting to a server', function()
      local callbackTriggered = false
      clients[1]:onConnect(function() callbackTriggered = true end)
      server:startListening()
      assert.False(callbackTriggered)
      clients[1]:connect()
      assert.True(callbackTriggered)
    end)
    it('triggers onConnectFailure() callbacks when rejected by the server', function()
      server.handleConnectRequest = function(self, client, handshake, accept, reject)
        reject('Test rejection message')
      end
      local rejectReason = nil
      clients[1]:onConnectFailure(function(reason) rejectReason = reason end)
      server:startListening()
      clients[1]:connect()
      assert.is.equal('Test rejection message', rejectReason)
    end)
    it('triggers onDisconnect() callbacks when disconnecting from a server', function()
      local callbackTriggered = false
      clients[1]:onDisconnect(function(reason) callbackTriggered = true end)
      server:startListening()
      clients[1]:connect()
      assert.False(callbackTriggered)
      clients[1]:disconnect('Disconnect reason')
      assert.True(callbackTriggered)
    end)
  end)
  describe('with latency', function()
    it('takes time for a connection request to be processed', function()
      createNetwork({ latency = 20 })
      -- Client sends a connection request
      server:startListening()
      clients[1]:connect()
      -- Request hasn't even been received by the server yet
      assert.is.equal(0, #server:getClients())
      assert.False(clients[1]:isConnected())
      -- Client and server have both recognized the connection
      progressTime(1.05)
      assert.is.equal(1, #server:getClients())
      assert.True(clients[1]:isConnected())
    end)
    -- it('takes time for the client to receive a message', function()
    --   createNetwork({ latency = 1000 })
    --   local messageReceived
    --   clients[1]:onReceive(function(msg) messageReceived = msg end)
    --   -- Client connects
    --   server:startListening()
    --   clients[1]:connect()
    --   progressTime(5.05)
    --   -- Server sends a message
    --   server:sendAll('Test message from server')
    --   assert.is.falsy(messageReceived)
    --   -- Client receives the message
    --   progressTime(1.05)
    --   assert.is.equal('Test message from server', messageReceived)
    -- end)
    -- it('takes time for the server to receive a message', function()
    --   createNetwork({ latency = 1000 })
    --   local messageReceived
    --   server:onReceive(function(client, msg) messageReceived = msg end)
    --   -- Client connects
    --   server:startListening()
    --   clients[1]:connect()
    --   progressTime(5.05)
    --   -- Client sends a message
    --   clients[1]:send('Test message from client')
    --   assert.is.falsy(messageReceived)
    --   -- Server receives the message
    --   progressTime(1.05)
    --   assert.is.equal('Test message from client', messageReceived)
    -- end)
  end)
  describe('with unreliability', function()
    -- it('the server has a chance of never receiving packets that are sent to it', function()
    --   createNetwork({ packetLossChance = 0.5 })
    --   local numMessagesReceived = 0
    --   server:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --   server:startListening()
    --   clients[1]:connect()
    --   for i = 1, 100 do
    --     clients[1]:send('Test message from client')
    --   end
    --   assert.True(25 < numMessagesReceived and numMessagesReceived < 75)
    -- end)
    -- it('the client has a chance of never receiving packets that are sent to it', function()
    --   createNetwork({ packetLossChance = 0.5 })
    --   local numMessagesReceived = 0
    --   clients[1]:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --   server:startListening()
    --   clients[1]:connect()
    --   for i = 1, 100 do
    --     server:sendAll('Test message from server')
    --   end
    --   assert.True(25 < numMessagesReceived and numMessagesReceived < 75)
    -- end)
    -- describe('with latency', function()
    --   it('the server has a chance of never receiving packets that are sent to it', function()
    --     createNetwork({ packetLossChance = 0.5, latency = 100 })
    --     local numMessagesReceived = 0
    --     server:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --     server:startListening()
    --     clients[1]:connect()
    --     progressTime(0.505)
    --     for i = 1, 100 do
    --       progressTime(0.105)
    --       clients[1]:send('Test message from client')
    --     end
    --     progressTime(1.000)
    --     assert.True(25 < numMessagesReceived and numMessagesReceived < 75)
    --   end)
    --   it('the client has a chance of never receiving packets that are sent to it', function()
    --     createNetwork({ packetLossChance = 0.5, latency = 100 })
    --     local numMessagesReceived = 0
    --     clients[1]:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --     server:startListening()
    --     clients[1]:connect()
    --     progressTime(0.505)
    --     for i = 1, 100 do
    --       progressTime(0.105)
    --       server:sendAll('Test message from server')
    --     end
    --     progressTime(1.000)
    --     assert.True(25 < numMessagesReceived and numMessagesReceived < 75)
    --   end)
    -- end)
  end)
  describe('without any unreliability', function()
    -- it('the server receives every packet sent to it', function()
    --   local numMessagesReceived = 0
    --   server:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --   server:startListening()
    --   clients[1]:connect()
    --   for i = 1, 100 do
    --     clients[1]:send('Test message from client')
    --   end
    --   assert.is.equal(numMessagesReceived, 100)
    -- end)
    -- it('the client receives every packet sent to it', function()
    --   local numMessagesReceived = 0
    --   clients[1]:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --   server:startListening()
    --   clients[1]:connect()
    --   for i = 1, 100 do
    --     server:sendAll('Test message from server')
    --   end
    --   assert.is.equal(numMessagesReceived, 100)
    -- end)
    -- describe('with latency', function()
    --   it('the server receives every packet sent to it', function()
    --     createNetwork({ latency = 100 })
    --     local numMessagesReceived = 0
    --     server:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --     server:startListening()
    --     clients[1]:connect()
    --     progressTime(0.505)
    --     for i = 1, 100 do
    --       progressTime(0.105)
    --       clients[1]:send('Test message from client')
    --     end
    --     progressTime(1.000)
    --     assert.is.equal(numMessagesReceived, 100)
    --   end)
    --   it('the client receives every packet sent to it', function()
    --     createNetwork({ latency = 100 })
    --     local numMessagesReceived = 0
    --     clients[1]:onReceive(function(client, msg) numMessagesReceived = numMessagesReceived + 1 end)
    --     server:startListening()
    --     clients[1]:connect()
    --     progressTime(0.505)
    --     for i = 1, 100 do
    --       progressTime(0.105)
    --       server:sendAll('Test message from server')
    --     end
    --     progressTime(1.000)
    --     assert.is.equal(numMessagesReceived, 100)
    --   end)
    -- end)
  end)
end)
