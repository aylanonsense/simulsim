-- These are the client/server callbacks that simulsim defines
-- If you run this you should see the client connecting to the server in the developer console

-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/master/simulsim.lua'

-- Define a trivially boring game (nothing happens)
local game = simulsim.defineGame()

-- Create a client-server network for the (trivially boring) game to run on
local network, server, client = simulsim.createGameNetwork(game, { mode = 'multiplayer' })

-- Server-side callbacks
-- Called when the server first loads
function server.load()
  print('server.load')
end
-- Called once per frame
function server.update(dt) end
-- Called whenever a client connects to the server
function server.clientconnected(client)
  print('server.clientconnected clientId=' .. client.clientId)
end
-- Called whenever a client disconnects from the server
function server.clientdisconnected(client, reason)
  print('server.clientdisconnected clientId=' .. client.clientId .. ' reason="' .. reason .. '"')
end

-- Client-side callbacks
-- Called when the client first loads
function client.load()
  print('client.load')
end
-- Called once per frame
function client.update(dt) end
-- Called whenever the client is ready to draw the game state to the screen
function client.draw() end
-- Called whenever a key is pressed client-side
-- Similar callbacks exist for all the love callbacks (e.g. mousepressed)
function client.keypressed(key)
  print('client.keypressed key=' .. key)
end
-- Called when the client connects to the server
function client.connected()
  print('client.connected clientId=' .. client.clientId)
end
-- Called when the client fails to connect to the server
function client.connectfailed(reason)
  print('client.connectfailed reason="' .. reason .. '"')
end
-- Calle when the client gets disconnected from the server
function client.disconnected(reason)
  print('client.disconnected reason="' .. reason .. '"')
end
-- Called whenever the client starts to feel it has a good read on the latency
function client.synced()
  print('client.synced')
end
-- Called whenever the client gets desynchronized from the server and needs to reevaluate latency
function client.desynced()
  print('client.desynced')
end
