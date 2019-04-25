-- Load dependencies
local simulsim = require 'simulsim'

-- print(castle.system.isRemoteServer())
print(CASTLE_SERVER)

-- Create a new game simulation
local simulationDefinition = simulsim.defineSimulation({
  initialState = {},
  handleEvent = function(self, eventType, eventData)
    if eventType == 'spawn-player-entity' then
      self:spawnEntity({
        type = 'player',
        clientId = eventData.clientId,
        x = eventData.x,
        y = eventData.y,
        width = 20,
        height = 20,
        color = eventData.color
      })
    elseif eventType == 'change-player-color' then
      for _, entity in ipairs(self.entities) do
        if entity.clientId == eventData.clientId then
          entity.color = eventData.color
          break
        end
      end
    end
  end,
  update = function(self, dt)
    for _, entity in ipairs(self.entities) do
      local inputs = self.inputs[entity.clientId] or {}
      entity.x = entity.x + 100 * dt * ((inputs.right and 1 or 0) - (inputs.left and 1 or 0))
      entity.y = entity.y + 100 * dt * ((inputs.down and 1 or 0) - (inputs.up and 1 or 0))
    end
  end
})

-- Game params
local network

function isEntityUsingClientSidePrediction(self, entity)
  return entity.clientId == self.clientId
end

function love.load()
  -- Create a new network
  USE_CASTLE_CONFIG = false
  network = simulsim.createNetworkedSimulation({
    simulationDefinition = simulationDefinition,
    useFakeNetwork = false
  })
  -- Start the network
  network.server:startListening()
  network.server:onConnect(function(client)
    network.server:fireEvent('spawn-player-entity', {
      clientId = client.clientId,
      x = math.random(10, 270),
      y = math.random(60, 270),
      color = { math.random(), math.random(), math.random() }
    })
  end)
  network.client.isEntityUsingClientSidePrediction = isEntityUsingClientSidePrediction
  network.client:simulateNetworkConditions({
    latency = 100,
    latencyDeviation = 10,
    packetLossChance = 0.00
  })
  network.client:connect()
end

function love.update(dt)
  network.client:setInputs({
    up = love.keyboard.isDown('w'),
    left = love.keyboard.isDown('a'),
    down = love.keyboard.isDown('s'),
    right = love.keyboard.isDown('d')
  })
  -- Update the network
  network:update(dt)
end

function love.draw()
  -- Draw the server and the clients
  drawSimulation(network.server:getSimulation(), nil, 160, 10, 300, 300, true, 'SERVER')
  drawSimulation(network.client:getSimulationWithoutPrediction(), nil, 160, 10, 300, 300, false)
  drawSimulation(network.client:getSimulation(), network.client, 160, 320, 300, 300, true, 'CLIENT - WASD')
  drawSimulation(network.client:getSimulationWithoutPrediction(), network.client, 160, 320, 300, 300, false)
end

function love.keypressed(key)
  if key == 'lshift' then
    network.client:fireEvent('change-player-color', {
      clientId = network.client.clientId,
      color = { math.random(), math.random(), math.random() }
    })
  end
end

function drawSimulation(sim, client, x, y, width, height, fullRender, title)
  if fullRender then
    love.graphics.setColor(0.5, 0.5, 0.5)
    love.graphics.rectangle('fill', x, y, width, height)
  end
  -- Draw entities
  for _, entity in ipairs(sim.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle(fullRender and 'fill' or 'line', x + entity.x, y + entity.y, entity.width, entity.height)
    if fullRender then
      love.graphics.setColor(0, 0, 0)
      love.graphics.print(entity.clientId, x + entity.x + 6, y + entity.y + 4)
    end
  end
  -- Draw network info
  if fullRender then
    love.graphics.setColor(0, 0, 0)
    love.graphics.print(title, x + 4, y + 2)
    love.graphics.print('sim time: ' .. math.floor(sim.frame / 60), x + 4, y + 18)
    if client then
      love.graphics.print('client id: ' .. (client.clientId or '--'), x + 4, y + 34)
      love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 50)
    end
  end
end
