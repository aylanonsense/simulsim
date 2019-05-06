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
  mode = 'test',
  numClients = 2,
  gameDefinition = gameDef
})

for clientIndex, client in ipairs(clients) do
  function client.load()
    client.simulateNetworkConditions({
      latency = 500,
      latencyDeviation = 150
    })
  end

  function client.update(dt)
    if clientIndex == 1 then
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

  -- Change colors by pressing the C key
  function client.keypressed(key)
    if clientIndex == 1 and key == 'lshift' then
      client.fireEvent('change-color', { clientId = client.clientId, color = { math.random(), math.random(), math.random() } })
    elseif clientIndex == 2 and key == 'rshift' then
      client.fireEvent('change-color', { clientId = client.clientId, color = { math.random(), math.random(), math.random() } })
    end
  end

  -- Draw the game
  function client.draw()
    local x = (clientIndex - 1) * 310
    local y = 0
    -- Reset the canvas
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle('fill', x, 0, 300, 300)
    -- Draw entities
    for _, entity in ipairs(client.getGameWithoutPrediction().entities) do
      love.graphics.setColor(entity.color)
      love.graphics.rectangle('line', x + entity.x, entity.y, 20, 20)
    end
    for _, entity2 in ipairs(client.getGame().entities) do
      love.graphics.setColor(entity2.color)
      love.graphics.rectangle('fill', x + entity2.x, entity2.y, 20, 20)
    end
    -- Draw network stats
    love.graphics.setColor(0, 0, 0)
    love.graphics.print('client id: ' .. (client.clientId or '--'), x + 4, y + 2)
    love.graphics.print('status: ' .. (client.isSynced() and 'synced' or (client.isConnected() and 'syncing' or (client.isConnecting() and 'connecting' or 'disconnected'))), x + 4, y + 18)
    love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 34)
  end
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
