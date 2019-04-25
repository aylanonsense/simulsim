-- Load dependencies
local ShareConnectionListener = require 'src/network/ShareConnectionListener'
local ShareConnection = require 'src/network/ShareConnection'
local Server = require 'src/simulationNetwork/Server'
local Client = require 'src/simulationNetwork/Client'

-- Creates a fake, in-memory network of clients and servers
return function(params)
  params = params or {}
  local simulationDefinition = params.simulationDefinition

  -- Create the server
  local listener = ShareConnectionListener:new()
  local server = Server:new({
    simulationDefinition = simulationDefinition,
    listener = listener
  })

  -- Create the client
  local clientConn = ShareConnection:new()
  local client = Client:new({
    simulationDefinition = simulationDefinition,
    conn = clientConn
  })

  -- Return them all
  return server, client
end
