-- This is a demo of simulsim's development functionality, which lets you
-- simulate a multiplayer game with multiple clients on one computer

-- Load simulsim as a dependency (you should use a GitHub url for a specific commit)
local simulsim = require 'simulsim'

-- Create the exact same game as seen in simple-example.lua
local game = simulsim.defineGame()
function game.load(self)
  self.data.backgroundColor = { 0.1, 0.1, 0.1 }
end
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    local inputs = self:getInputsForClient(entity.clientId) or {}
    local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
    local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
    entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
    entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
  end
end
function game.handleEvent(self, eventType, eventData)
  if eventType == 'spawn-player' then
    self:spawnEntity({
      clientId = eventData.clientId,
      x = eventData.x,
      y = eventData.y,
      width = 20,
      height = 20,
      color = eventData.color
    })
  elseif eventType == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = eventData.clientId }))
  end
end

-- When running the game locally, simulsim will run in development mode
-- In development mode, you can specify how many simulated clients you'd like to have connect to the server
-- This lets you preview what your game will look like once it's fully deployed to a remote server!
local network, server, client = simulsim.createGameNetwork(game, {
  width = 400, -- need to specify width/height for proper development mode rendering, won't be necessary in the future
  height = 400,
  -- Force development mode to be enabled
  mode = 'development',
  -- Add 4 clients, and display them in a grid
  numClients = 4,
  -- Set up each client to have 250 ms of latency
  latency = 250,
  latencyDeviation = 50,
  latencySpikeChance = 0.00,
  packetLossChance = 0.00
})

-- Set up the exact same server as seen in simple-example.lua
function server.clientconnected(self, client)
  self:fireEvent('spawn-player', {
    clientId = client.clientId,
    x = 100 + 200 * math.random(),
    y = 100 + 200 * math.random(),
    color = { math.random(), 1, math.random() }
  })
end
function server.clientdisconnected(self, client)
  self:fireEvent('despawn-player', { clientId = client.clientId })
end

-- Only send inputs if the client is highlighted, meaning only if the mouse is hovered over that client's render area
function client.update(self, dt)
  if self:isHighlighted() then
    self:setInputs({
      up = love.keyboard.isDown('w') or love.keyboard.isDown('up'),
      left = love.keyboard.isDown('a') or love.keyboard.isDown('left'),
      down = love.keyboard.isDown('s') or love.keyboard.isDown('down'),
      right = love.keyboard.isDown('d') or love.keyboard.isDown('right')
    })
  end
end
function client.draw(self, x, y, scale)
  love.graphics.setColor(self.game.data.backgroundColor)
  love.graphics.rectangle('fill', 0, 0, 400, 400)
  for _, entity in ipairs(self.game.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, entity.width, entity.height)
  end
end
