-- Load dependencies
local simulsim = require 'simulsim'

local gameDef = simulsim.defineGame({
  update = function(self, dt)
    for _, entity in ipairs(self.entities) do
      local inputs = self.inputs[entity.clientId] or {}
      entity.x = math.min(math.max(0, entity.x + 100 * dt * ((inputs.right and 1 or 0) - (inputs.left and 1 or 0))), 280)
      entity.y = math.min(math.max(0, entity.y + 100 * dt * ((inputs.down and 1 or 0) - (inputs.up and 1 or 0))), 280)
    end
  end,
  handleEvent = function(self, type, data)
    if type == 'spawn-player' then
      self:spawnEntity({
        clientId = data.clientId,
        x = data.x,
        y = data.y,
        color = data.color
      })
    elseif type == 'change-color' then
      for _, entity in ipairs(self.entities) do
        if entity.clientId == data.clientId then
          entity.color = data.color
        end
      end
    end
  end
})

local server, client, clients = simulsim.createGameNetwork({
  mode = 'multiplayer',
  gameDefinition = gameDef
})

-- Connect the client to the server
function client.load()
  client.connect()
end

-- Move by pressing left/right
function client.update(dt)
  client.setInputs({
    up = love.keyboard.isDown('up') or love.keyboard.isDown('w'),
    left = love.keyboard.isDown('left') or love.keyboard.isDown('a'),
    down = love.keyboard.isDown('down') or love.keyboard.isDown('s'),
    right = love.keyboard.isDown('right') or love.keyboard.isDown('d')
  })
end

-- Change colors by pressing the C key
function client.keypressed(key)
  if key == 'c' then
    client.fireEvent('change-color', { clientId = client.clientId, color = { math.random(), math.random(), math.random() } })
  end
end

-- Draw the game
function client.draw()
  -- Reset the canvas
  love.graphics.setColor(0.5, 0.5, 0.5)
  love.graphics.rectangle('fill', 0, 0, 300, 300)
  -- Draw entities
  for _, entity in ipairs(client.getGame().entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', entity.x, entity.y, 20, 20)
  end
end

-- Start the server
function server.load()
  server.startListening()
end

-- Whenever a client connects, spawn an entity for that player
function server.clientconnected(client)
  server.fireEvent('spawn-player', {
    clientId = client.clientId,
    x = math.random(10, 280),
    y = math.random(10, 280),
    color = { math.random(), math.random(), math.random() }
  })
end

-- Manually call load methods for now
if server.load then
  server.load()
end
for _, client in ipairs(clients) do
  if client.load then
    client.load()
  end
end
