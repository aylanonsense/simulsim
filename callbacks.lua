-- Load dependencies
local simulsim = require 'simulsim'

local server, client, clients = simulsim.createGameNetwork({
  mode = 'test',
  numClients = 2,
  gameDefinition = simulsim.defineGame()
})

for _, client in ipairs(clients) do
  function client.load()
    print('client.load [' .. (client.clientId or '?') .. ']')
  end
  function client.update(dt) end
  function client.draw() end
  function client.connected()
    print('client.connected [' .. (client.clientId or '?') .. ']')
  end
  function client.connectfailed()
    print('client.connectfailed [' .. (client.clientId or '?') .. ']')
  end
  function client.synced()
    print('client.synced [' .. (client.clientId or '?') .. ']')
  end
  function client.desynced()
    print('client.desynced [' .. (client.clientId or '?') .. ']')
  end
  function client.disconnected()
    print('client.disconnected [' .. (client.clientId or '?') .. ']')
  end
  function client.keypressed(key)
    print('client.keypressed [' .. (client.clientId or '?') .. ']')
    if key == 'd' then
      client.disconnect()
    end
  end
end

function server.load()
  print('server.load')
end
function server.update(dt) end
function server.clientconnected(client)
  print('server.clientconnected [' .. (client.clientId or '?') .. ']')
end
function server.clientdisconnected(client)
  print('server.clientdisconnected [' .. (client.clientId or '?') .. ']')
end
