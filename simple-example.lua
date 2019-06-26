-- This is a very simple example game meant to teach you the basics of simulsim
-- It's just a bunch of squares running around together

-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'simulsim'

-- Define a new game
local game = simulsim.defineGame()

-- When the game is first loaded, set the background color
function game.load(self)
  self.data.backgroundColor = { 0.1, 0.1, 0.1 }
end

-- Update the game's state every frame by moving each entity
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    local inputs = self:getInputsForClient(entity.clientId) or {}
    local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
    local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
    entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
    entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
  end
end

-- Handle events that the server and client fire, which may end up changing the game state
function game.handleEvent(self, eventType, eventData)
  -- Spawn a new player entity for a client
  if eventType == 'spawn-player' then
    self:spawnEntity({
      clientId = eventData.clientId,
      x = eventData.x,
      y = eventData.y,
      width = 20,
      height = 20,
      color = eventData.color
    })
  -- Despawn a player
  elseif eventType == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
  end
end

-- Create a client-server network for the game to run on
local network, server, client = simulsim.createGameNetwork(game)

-- When a client connects to the server, spawn a playable entity for them to control
function server.clientconnected(client)
  server.fireEvent('spawn-player', {
    clientId = client.clientId,
    x = 100 + 80 * math.random(),
    y = 100 + 80 * math.random(),
    color = { math.random(), 1, math.random() }
  })
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
  love.graphics.setColor(client.game.data.backgroundColor)
  love.graphics.rectangle('fill', 0, 0, 400, 400)
  -- Draw each entity
  for _, entity in ipairs(client.game.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
  end
end
