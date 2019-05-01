-- Load dependencies
local LocalTransportStream = require 'src/network/LocalTransportStream'
local LocalConnectionListener = require 'src/network/LocalConnectionListener'
local LocalConnection = require 'src/network/LocalConnection'
local ShareConnectionListener = require 'src/network/ShareConnectionListener'
local ShareConnection = require 'src/network/ShareConnection'
local Server = require 'src/simulationNetwork/Server'
local Client = require 'src/simulationNetwork/Client'
local EmptyServer = require 'src/simulationNetwork/EmptyServer'
local EmptyClient = require 'src/simulationNetwork/EmptyClient'

function createNetwork(params)
  params = params or {}
  local mode = params.mode or 'test'

  -- Create an in-memory network, which allows for neat things like simulating network conditions
  if mode == 'test' then
    return createInMemoryNetwork(params)
  -- Create a localhost network using share.lua, though others won't be able to join
  elseif mode == 'localhost' then
    USE_CASTLE_CONFIG = false
    return createLocalhostShareNetwork(params)
  -- Create a fully multiplayer network using share.lua which will require a dedicated server
  elseif mode == 'multiplayer' then
    USE_CASTLE_CONFIG = true
    -- We're on the server, so just create a server network
    if CASTLE_SERVER then
      return createServerSideShareNetwork(params)
    -- We're on the client, so just create a client network
    else
      return createClientSideShareNetwork(params)
    end
  end
end

function createInMemoryNetwork(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition
  local numClients = params.numClients or 1

  -- Keep track of transport streams
  local transportStreams = {}

  -- Create the server
  local listener = LocalConnectionListener:new()
  local server = Server:new({
    simulationDefinition = simulationDefinition,
    listener = listener
  })

  -- Create the clients
  local clients = {}
  for i = 1, numClients do
    -- Create the transport Streams
    local clientToServer = LocalTransportStream:new()
    local serverToClient = LocalTransportStream:new()
    table.insert(transportStreams, clientToServer)
    table.insert(transportStreams, serverToClient)

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
    local client = Client:new({
      simulationDefinition = simulationDefinition,
      conn = clientConn
    })
    table.insert(clients, client)
  end

  -- Return an in-memory network
  return {
    -- Private vars
    _transportStreams = transportStreams,

    -- Public vars
    server = server,
    client = clients[1],
    clients = clients,

    -- Public methods
    update = function(self, dt)
      self.server:update(dt)
      for _, client in ipairs(self.clients) do
        client:update(dt)
      end
      for _, transportStream in ipairs(self._transportStreams) do
        transportStream:update(dt)
      end
    end,
    moveForwardOneFrame = function(self, dt)
      self.server:moveForwardOneFrame(dt)
      for _, client in ipairs(self.clients) do
        client:moveForwardOneFrame(dt)
      end
    end,
    isServerSide = function(self)
      return true
    end,
    isClientSide = function(self)
      return true
    end
  }
end

function createLocalhostShareNetwork(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition
  local port = params.port

  -- Create the server
  local server = Server:new({
    simulationDefinition = simulationDefinition,
    listener = ShareConnectionListener:new({
      isLocalhost = true,
      port = port
    })
  })

  -- Create the client
  local client = Client:new({
    simulationDefinition = simulationDefinition,
    conn = ShareConnection:new({
      isLocalhost = true,
      port = port
    })
  })

  -- Return a localhost network that uses share.lua
  return {
    -- Public vars
    server = server,
    client = client,
    clients = { client },

    -- Public methods
    update = function(self, dt)
      self.server:update(dt)
      self.client:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      self.server:moveForwardOneFrame(dt)
      self.client:moveForwardOneFrame(dt)
    end,
    isServerSide = function(self)
      return true
    end,
    isClientSide = function(self)
      return true
    end
  }
end

function createServerSideShareNetwork(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition

  -- Create the server
  local server = Server:new({
    simulationDefinition = simulationDefinition,
    listener = ShareConnectionListener:new({
      isLocalhost = false
    })
  })

  -- Create a fake client
  local client = EmptyClient:new()

  -- Return a localhost network that uses share.lua
  return {
    -- Public vars
    server = server,
    client = client,
    clients = { client },

    -- Public methods
    update = function(self, dt)
      self.server:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      self.server:moveForwardOneFrame(dt)
    end,
    isServerSide = function(self)
      return true
    end,
    isClientSide = function(self)
      return false
    end
  }
end

function createClientSideShareNetwork(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition

  -- Create a fake server
  local server = EmptyServer:new()

  -- Create the client
  local client = Client:new({
    simulationDefinition = simulationDefinition,
    conn = ShareConnection:new({
      isLocalhost = false
    })
  })

  -- Return a localhost network that uses share.lua
  return {
    -- Public vars
    server = server,
    client = client,
    clients = { client },

    -- Public methods
    update = function(self, dt)
      self.client:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      self.client:moveForwardOneFrame(dt)
    end,
    isServerSide = function(self)
      return false
    end,
    isClientSide = function(self)
      return true
    end
  }
end

return createNetwork
