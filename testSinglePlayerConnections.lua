-- Sets up a local (faked) client <-> server architecture

-- Load dependencies
local TransportLayer = require 'src/singlePlayer/TransportLayer'
local Connection = require 'src/singlePlayer/Connection'

function love.update(dt)
  TransportLayer:updateAll(dt)
end

-- Connection vars
local clientConn, serverConn = Connection:createConnectionPair()

-- Loggings
clientConn:onConnect(function()
  print('CLIENT: Connected')
end)
clientConn:onDisconnect(function(reason)
  print('CLIENT: Disconnected because "' .. (reason or '') .. '"')
end)
clientConn:onReceive(function(msg)
  print('CLIENT: Received "' .. msg .. '"')
end)
serverConn:onConnect(function()
  print('SERVER: Connected')
end)
serverConn:onDisconnect(function(reason)
  print('SERVER: Disconnected because "' .. (reason or '') .. '"')
end)
serverConn:onReceive(function(msg)
  print('SERVER: Received "' .. msg .. '"')
end)

-- Connect
serverConn:onConnect(function()
  serverConn:send('Message from server (after connect)')
end)
clientConn:onConnect(function()
  clientConn:send('Message from client (after connect)')
end)
clientConn:connect()
serverConn:send('Message from server (immediate)')
clientConn:send('Message from client (immediate)')
clientConn:disconnect()
