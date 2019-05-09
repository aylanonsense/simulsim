-- Load dependencies
local simulsim = require 'simulsim'

print('simple.lua loaded')

local network = simulsim.createGameNetwork({
  mode = 'multiplayer',
  gameDefinition = simulsim.defineGame({})
})
local server, client = network.server, network.client

print('network created')

function server.load()
  print('server.load')
end

function server.clientconnected(client)
  print('server.clientconnected ' .. (client.clientId or '--'))
end

function server.clientdisconnected(client)
  print('server.clientdisconnected ' .. (client.clientId or '--'))
end

function client.load()
  print('client.load')
end

function client.connected()
  print('client.connected ' .. (client.clientId or '--'))
end

function client.connectfailed(reason)
  print('client.connectfailed ' .. (reason or '--'))
end

function client.disconnected()
  print('client.disconnected')
end
