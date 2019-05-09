-- This is a very simple example game meant to teach you the basics of simulsim
-- It's just a bunch of squares running around together

-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/master/simulsim.lua'

-- Define a new game
local game = simulsim.defineGame()

-- Update the game's state every frame by moving each entity
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    local inputs = self.inputs[entity.clientId] or {}
    local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
    local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
    entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
    entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
  end
end

-- Handle events that the server and client fire, which may end up changing the game state
function game.handleEvent(self, type, data)
  -- Spawn a new player entity for a client
  if type == 'spawn-player' then
    self:spawnEntity({
      clientId = data.clientId,
      color = data.color,
      x = 190,
      y = 190
    })
  -- Despawn a player
  elseif type == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = data.clientid }))
  end
end

-- Create a client-server network for the game to run on
local network, server, client = simulsim.createGameNetwork(game, { mode = 'multiplayer' })

-- When a client connects to the server, spawn a playable entity for them to control
function server.clientconnected(client)
  server.fireEvent('spawn-player', { clientId = client.clientId, color = { math.random(), 1, math.random() } })
end

-- When a client disconnects from the server, despawn their player entity
function server.clientdisconnected(client)
  server.fireEvent('despawn-player', { clientId = client.clientId })
end

-- Every frame the client tells the server which buttons it's pressing
function client.update(dt)
  client.setInputs({
    up = love.keyboard.isDown('w') or love.keyboard.isDown('up'),
    left = love.keyboard.isDown('a') or love.keyboard.isDown('left'),
    down = love.keyboard.isDown('s') or love.keyboard.isDown('down'),
    right = love.keyboard.isDown('d') or love.keyboard.isDown('right')
  })
end

-- Draw the game for each client
function client.draw()
  -- Clear the screen
  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.rectangle('fill', 0, 0, 400, 400)
  -- Draw each entity
  for _, entity in ipairs(client.game.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, 20, 20)
  end
end
