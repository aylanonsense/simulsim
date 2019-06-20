-- This is a very simple example game meant to teach you the basics of simulsim
-- It's just a bunch of squares running around together

-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'simulsim'

simulsim.setLogLevel('INFO')

local latency = 200

-- Define a new game
local game = simulsim.defineGame()

-- Create a client-server network for the game to run on
local network, server, client = simulsim.createGameNetwork(game, { mode = 'multiplayer', cullRedundantEvents = false, numClients = 1 })

function server.update(dt)
end