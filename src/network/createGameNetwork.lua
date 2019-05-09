-- Load dependencies
local LocalTransportStream = require 'src/transport/LocalTransportStream'
local LocalConnectionListener = require 'src/transport/LocalConnectionListener'
local LocalConnection = require 'src/transport/LocalConnection'
local ShareConnectionListener = require 'src/transport/ShareConnectionListener'
local ShareConnection = require 'src/transport/ShareConnection'
local GameServer = require 'src/client-server/GameServer'
local GameClient = require 'src/client-server/GameClient'
local EmptyGameServer = require 'src/client-server/EmptyGameServer'
local EmptyGameClient = require 'src/client-server/EmptyGameClient'

function createNetwork(params)
  params = params or {}
  local mode = params.mode or 'development'

  -- Create an in-memory network, which allows for neat things like simulating network conditions
  if mode == 'development' then
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
  local gameDefinition = params.gameDefinition
  local numClients = params.numClients or 1
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenServerSnapshots = params.framesBetweenServerSnapshots or 35

  -- Keep track of transport streams
  local transportStreams = {}

  -- Create the server
  local listener = LocalConnectionListener:new()
  local server = GameServer:new({
    gameDefinition = gameDefinition,
    listener = listener,
    framesBetweenFlushes = framesBetweenFlushes,
    framesBetweenSnapshots = framesBetweenServerSnapshots
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
    local client = GameClient:new({
      gameDefinition = gameDefinition,
      conn = clientConn,
      framesBetweenFlushes = framesBetweenFlushes
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
  local gameDefinition = params.gameDefinition
  local port = params.port
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenServerSnapshots = params.framesBetweenServerSnapshots or 35

  -- Create the server
  local server = GameServer:new({
    gameDefinition = gameDefinition,
    listener = ShareConnectionListener:new({
      isLocalhost = true,
      port = port
    }),
    framesBetweenFlushes = framesBetweenFlushes,
    framesBetweenSnapshots = framesBetweenServerSnapshots
  })

  -- Create the client
  local client = GameClient:new({
    gameDefinition = gameDefinition,
    conn = ShareConnection:new({
      isLocalhost = true,
      port = port
    })
    framesBetweenFlushes = framesBetweenFlushes
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
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenServerSnapshots = params.framesBetweenServerSnapshots or 35

  -- Create the server
  local server = GameServer:new({
    gameDefinition = gameDefinition,
    listener = ShareConnectionListener:new({
      isLocalhost = false
    }),
    framesBetweenFlushes = framesBetweenFlushes,
    framesBetweenSnapshots = framesBetweenServerSnapshots
  })

  -- Create a fake client
  local client = EmptyGameClient:new()

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
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenServerSnapshots = params.framesBetweenServerSnapshots or 35

  -- Create a fake server
  local server = EmptyGameServer:new()

  -- Create the client
  local client = GameClient:new({
    gameDefinition = gameDefinition,
    conn = ShareConnection:new({
      isLocalhost = false
    }),
    framesBetweenFlushes = framesBetweenFlushes
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
