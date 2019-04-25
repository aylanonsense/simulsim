-- Load dependencies
local LocalTransportStream = require 'src/network/LocalTransportStream'
local LocalConnectionListener = require 'src/network/LocalConnectionListener'
local LocalConnection = require 'src/network/LocalConnection'
local Server = require 'src/simulationNetwork/Server'
local Client = require 'src/simulationNetwork/Client'

-- Creates a fake, in-memory network of clients and servers
return function(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition
  local numClients = params.numClients or 1
  local transportStreamParams = {
    latency = params.latency,
    latencyDeviation = params.latencyDeviation,
    packetLossChance = params.packetLossChance
  }

  -- Keep track of the transport streams
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
    local clientToServer = LocalTransportStream:new(transportStreamParams)
    local serverToClient = LocalTransportStream:new(transportStreamParams)
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

  -- Return them all
  return server, clients, transportStreams
end
