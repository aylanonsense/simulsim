-- Load dependencies
local TransportLayer = require 'src/transport/FauxTransportLayer'
local Connection = require 'src/transport/FauxConnection'
local Server = require 'src/network/Server'
local Client = require 'src/network/Client'

-- Creates a fake, in-memory network of clients and servers
return function(params)
  local numClients = params and params.numClients or 1
  local transportLayerParams = {
    latency = params and params.latency,
    latencyDeviation = params and params.latencyDeviation,
    packetLossChance = params and params.packetLossChance
  }

  -- Keep track of the transport layers
  local transportLayers = {}

  -- Create the server
  local server = Server:new()

  -- Create the clients
  local clients = {}
  for i = 1, numClients do
    -- Create the transport layers
    local clientToServer = TransportLayer:new(transportLayerParams)
    local serverToClient = TransportLayer:new(transportLayerParams)
    table.insert(transportLayers, clientToServer)
    table.insert(transportLayers, serverToClient)

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
  return server, clients, transportLayers
end
