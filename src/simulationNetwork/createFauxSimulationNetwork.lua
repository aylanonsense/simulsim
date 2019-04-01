-- Load dependencies
local TransportLayer = require 'src/transport/FauxTransportLayer'
local Connection = require 'src/transport/FauxConnection'
local Server = require 'src/simulationNetwork/Server'
local Client = require 'src/simulationNetwork/Client'

-- Creates a fake, in-memory network of clients and servers
return function(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition
  local numClients = params.numClients or 1
  local transportLayerParams = {
    latency = params.latency,
    latencyDeviation = params.latencyDeviation,
    packetLossChance = params.packetLossChance
  }

  -- Keep track of the transport layers
  local transportLayers = {}

  -- Create the server
  local server = Server:new({
    simulationDefinition = simulationDefinition
  })

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
      simulationDefinition = simulationDefinition,
      conn = clientConn
    }))
  end

  -- Return them all
  return server, clients, transportLayers
end
