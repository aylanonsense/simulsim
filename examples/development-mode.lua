-- This is a demo of simulsim's development functionality, which lets you
-- simulate a multiplayer game with multiple clients on one computer.

-- Load simulsim as a dependency (you should use a url for a specific commit)
local simulsim = require 'https://raw.githubusercontent.com/bridgs/simulsim/master/simulsim.lua'

-- Create the exact same game as seen in simple.lua
local game = simulsim.defineGame()
function game.update(self, dt)
  for _, entity in ipairs(self.entities) do
    local inputs = self.inputs[entity.clientId] or {}
    local moveX = (inputs.right and 1 or 0) - (inputs.left and 1 or 0)
    local moveY = (inputs.down and 1 or 0) - (inputs.up and 1 or 0)
    entity.x = math.min(math.max(0, entity.x + 200 * moveX * dt), 380)
    entity.y = math.min(math.max(0, entity.y + 200 * moveY * dt), 380)
  end
end
function game.handleEvent(self, type, data)
  if type == 'spawn-player' then
    self:spawnEntity({
      clientId = data.clientId,
      x = data.x,
      y = data.y,
      width = 20,
      height = 20,
      color = data.color
    })
  elseif type == 'despawn-player' then
    self:despawnEntity(self:getEntityWhere({ clientId = data.clientid }))
  end
end

-- With mode = 'development', simulsim will simulate a multiplayer network in-memory
-- In development mode, you can specify how many clients you'd like to have connect to the server
-- This lets you preview what your game will look like once it's fully deployed to a remote server!
local network, server = simulsim.createGameNetwork(game, {
  mode = 'development',
  numClients = 2
})

-- Set up the exact same server as seen in simple.lua
function server.clientconnected(client)
  server.fireEvent('spawn-player', {
    clientId = client.clientId,
    x = 100 + 80 * math.random(),
    y = 100 + 80 * math.random(),
    color = { math.random(), 1, math.random() }
  })
end
function server.clientdisconnected(client)
  server.fireEvent('despawn-player', { clientId = client.clientId })
end

-- Because numClients = 2, we have two clients to set up handlers for
for clientIndex, client in ipairs(network.clients) do
  local isLeftPlayer = clientIndex == 1

  -- For both clients, pretend they're on a reliable network with 250ms of latency
  -- (we can customize this to see how our game will perform in different network conditions)
  function client.load()
    client.simulateNetworkConditions({
      latency = 250,
      latencyDeviation = 0,
      packetLossChance = 0.00
    })
  end

  -- The left client will send WASD inputs to the server, the right player will use arrow keys
  function client.update(dt)
    if isLeftPlayer then
      client.setInputs({
        up = love.keyboard.isDown('w'),
        left = love.keyboard.isDown('a'),
        down = love.keyboard.isDown('s'),
        right = love.keyboard.isDown('d')
      })
    else
      client.setInputs({
        up = love.keyboard.isDown('up'),
        left = love.keyboard.isDown('left'),
        down = love.keyboard.isDown('down'),
        right = love.keyboard.isDown('right')
      })
    end
  end

  -- Draw both clients' games to the screen at once!
  function client.draw()
    -- Offset the drawn elements so that you can see both screens side-by-side
    local xOffset = isLeftPlayer and 0 or 410
    -- Clear the screen
    love.graphics.setColor(0.1, 0.1, 0.1)
    love.graphics.rectangle('fill', xOffset, 0, 400, 400)
    -- Draw each entity
    for _, entity in ipairs(client.game.entities) do
      love.graphics.setColor(entity.color)
      love.graphics.rectangle('fill', xOffset + entity.x, entity.y, entity.width, entity.height)
    end
  end
end
