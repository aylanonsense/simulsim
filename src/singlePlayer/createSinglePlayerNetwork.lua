-- Load dependencies
local TransportLayer = require 'src/singlePlayer/TransportLayer'
local Connection = require 'src/singlePlayer/Connection'
local Server = require 'src/singlePlayer/Server'

-- Creates a (fake) network suitable for single player simulations
return function(params)
  -- Create the transport layers
  local clientToServer = TransportLayer:new(params)
  local serverToClient = TransportLayer:new(params)

  -- Create the client connection
  local clientConn = Connection:new({
    isClient = true,
    sendTransportLayer = clientToServer,
    receiveTransportLayer = serverToClient
  })

  -- Create the server and server connection
  local server = Server:new()
  local serverConn = Connection:new({
    isClient = false,
    sendTransportLayer = serverToClient,
    receiveTransportLayer = clientToServer
  })
  serverConn:onConnect(function()
    server:handleConnect(serverConn)
  end)

  -- Return them
  return server, clientConn
end
