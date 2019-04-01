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
        table.insert(self.data.fruits, event.fruit)
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

  -- Helper function to pretend time has passed (by updating 60 times per second)
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
      server.handleClientConnectAttempt = function(self, client, accept, reject)
        accept({ color = 'red' })
      end
      server:startListening()
      clients[1]:connect()
      assert.is.same({ color = 'red' }, clients[1].data)
      assert.is.same({ color = 'red' }, server:getClients()[1].data)
    end)
    it('can reject clients that try to connect', function()
      server.handleClientConnectAttempt = function(self, client, accept, reject)
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
    it('triggers onConnect() callbacks when connecting to a server', function()
      local callbackTriggered = false
      clients[1]:onConnect(function() callbackTriggered = true end)
      server:startListening()
      assert.False(callbackTriggered)
      clients[1]:connect()
      assert.True(callbackTriggered)
    end)
    it('triggers onConnectFailure() callbacks when rejected by the server', function()
      server.handleClientConnectAttempt = function(self, client, accept, reject)
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
      createNetwork({ latency = 1000 })
      -- Client sends a connection request
      server:startListening()
      clients[1]:connect()
      -- Request hasn't even been received by the server yet
      assert.is.equal(0, #server:getClients())
      assert.False(clients[1]:isConnected())
      -- Client and server have both recognized the connection
      progressTime(5.05)
      assert.is.equal(1, #server:getClients())
      assert.True(clients[1]:isConnected())
    end)
  end)
end)
