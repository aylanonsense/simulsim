-- Tests to make sure a single player network actually works

-- Load dependencies
local TransportLayer = require 'src/singlePlayer/TransportLayer'
local createSinglePlayerNetwork = require 'src/singlePlayer/createSinglePlayerNetwork'

-- Send messages between client and server
function love.update(dt)
  TransportLayer:updateAll(dt)
end

-- Create the single player network
local server, client = createSinglePlayerNetwork()

-- Print out all network events
client:onConnect(function()
  print('CLIENT: Connected')
end)
client:onDisconnect(function(reason)
  print('CLIENT: Disconnected because "' .. (reason or '') .. '"')
end)
client:onReceive(function(msg)
  print('CLIENT: Received "' .. msg .. '" from server')
end)
server:onConnect(function(client)
  print('SERVER: Client ' .. client.clientId .. ' connected')
end)
server:onDisconnect(function(client, reason)
  print('SERVER: Client ' .. client.clientId .. ' disconnected because "' .. (reason or '') .. '"')
end)
server:onReceive(function(client, msg)
  print('SERVER: Received "' .. msg .. '" from client ' .. client.clientId)
end)

-- Test the network
server:startListening()
server:onConnect(function()
  server:sendAll('Message from server (after connect)')
end)
client:onConnect(function()
  client:send('Message from client (after connect)')
end)
client:connect()
server:sendAll('Message from server (immediate)')
client:send('Message from client (immediate)')
client:disconnect()
client:connect()
server:sendAll('Message from server (after reconnect)')
client:send('Message from client (after reconnect)')
client:disconnect()
