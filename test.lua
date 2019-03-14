-- Sets up a local (faked) client <-> server architecture

-- Load dependencies
local Server = require('./src/Server')
local Connection = require('./src/Connection')

-- Connection vars
local server
local clientConn

-- Create the server
server = Server:new()
server:onStart(function()
  print('SERVER: Started')
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

-- Create the server-side connection
serverConn = Connection:new()

-- Create the client-side connection
clientConn = Connection:new()
clientConn:onConnect(function()
  print('CLIENT: Connected to server')
end)
clientConn:onDisconnect(function(reason)
  print('CLIENT: Disconnected from server because "' .. (reason or '') .. '"')
end)
clientConn:onReceive(function(msg)
  print('CLIENT: Received "' .. msg .. '" from server')
end)

-- Connect the two connections together
serverConn:onSend(function(msg)
  if not clientConn:isConnected() then
    clientConn:connect()
  end
  clientConn:_receive(msg)
end)
serverConn:onDisconnect(function(reason)
  clientConn:disconnect()
end)
clientConn:onSend(function(msg)
  if not serverConn:isConnected() then
    serverConn:connect()
  end
  serverConn:_receive(msg)
end)
clientConn:onDisconnect(function(reason)
  serverConn:disconnect()
end)

-- Send some messages on connect
server:onConnect(function(client)
  client:send('1st message from server')
end)
clientConn:onConnect(function()
  clientConn:send('1st message from client')
end)

-- Connect everything
server:start()
serverConn:connect()
server:_connect(serverConn)
clientConn:connect()

-- Send some messages
clientConn:send('2nd message from client')
server:sendAll('2nd message from server')

-- Disconnect
clientConn:disconnect()
-- server:disconnectAll()

