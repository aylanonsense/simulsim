-- Load dependencies
local TransportLayer = require 'src/fauxNetwork/TransportLayer'
local Connection = require 'src/fauxNetwork/Connection'
local Server = require 'src/fauxNetwork/Server'
local Client = require 'src/fauxNetwork/Client'

-- Creates a fake, in-memory network of clients and servers
return function(params)
  local numClients = params and params.numClients or 1
  local transportLayerParams = {
    latency = params and params.latency,
    latencyDeviation = params and params.latencyDeviation,
    packetLossChance = params and params.packetLossChance
  }

  -- Create the server
  local server = Server:new()

  -- Create the clients
  local clients = {}
  for i = 1, numClients do
    -- Create the transport layers
    local clientToServer = TransportLayer:new(transportLayerParams)
    local serverToClient = TransportLayer:new(transportLayerParams)

    -- Create the server connection
    local serverConn = Connection:new({
      isClient = false,
      sendTransportLayer = serverToClient,
      receiveTransportLayer = clientToServer
    })
    serverConn:onConnect(function()
      server:handleConnect(serverConn)
    end)

    -- Create the client connection
    local clientConn = Connection:new({
      isClient = true,
      sendTransportLayer = clientToServer,
      receiveTransportLayer = serverToClient
    })
    table.insert(clients, Client:new({
      conn = clientConn
    }))
  end

  -- Return them both
  return server, clients
end
