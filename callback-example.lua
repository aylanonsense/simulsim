-- These are the client/server callbacks that simulsim defines
-- If you run this you should see the client connecting to the server in the developer console

-- Load simulsim as a dependency (you should use a GitHub url for a specific commit)
local simulsim = require 'simulsim'

-- Define a trivially boring game (nothing happens)
local game = simulsim.defineGame()

-- Create a client-server network for the game to run on
local network, server, client = simulsim.createGameNetwork(game)

-- Server-side callbacks
-- Called when the server first loads
function server.load(self)
  print('server.load')
end
-- Called once per frame
function server.update(self, dt) end
-- Called whenever a client connects to the server
function server.clientconnected(self, client)
  print('server.clientconnected clientId=' .. client.clientId)
end
-- Called whenever a client disconnects from the server
function server.clientdisconnected(self, client, reason)
  print('server.clientdisconnected clientId=' .. client.clientId .. ' reason="' .. reason .. '"')
end

-- Client-side callbacks
-- Called when the client first loads
function client.load(self)
  print('client.load')
end
-- Called once per frame
function client.update(self, dt) end
-- Called whenever the client is ready to draw the game state to the screen
function client.draw(self) end
-- Called whenever a key is pressed client-side
-- Similar callbacks exist for all the love callbacks (e.g. mousepressed)
function client.keypressed(self, key)
  print('client.keypressed key=' .. key)
end
function client.mousepressed(self, x, y)
  print('client.mousepressed x=' .. x .. ' y=' .. y)
end
-- Called when the client connects to the server
function client.connected(self)
  print('client.connected clientId=' .. self.clientId)
end
-- Called when the client fails to connect to the server
function client.connectfailed(self, reason)
  print('client.connectfailed reason="' .. reason .. '"')
end
-- Calle when the client gets disconnected from the server
function client.disconnected(self, reason)
  print('client.disconnected reason="' .. reason .. '"')
end
-- Called whenever the client starts to feel it has a good read on the latency and connection status
function client.stabilized(self)
  print('client.stabilized')
end
-- Called whenever the client begins to feel uncertain about latency and connection status
function client.destabilized(self)
  print('client.destabilized')
end
