-- Load dependencies
local simulsim = require 'simulsim'

local MODE = 'multiplayer'

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
  network = simulsim.createNetwork({
    simulationDefinition = simulationDefinition,
    mode = MODE,
    numClients = 2
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
  if network.clients[1] then
    network.clients[1].isEntityUsingClientSidePrediction = isEntityUsingClientSidePrediction
    network.clients[1]:simulateNetworkConditions({
      latency = 100,
      latencyDeviation = 10,
      packetLossChance = 0.00
    })
    network.clients[1]:connect()
  end
  if network.clients[2] then
    network.clients[2].isEntityUsingClientSidePrediction = isEntityUsingClientSidePrediction
    network.clients[2]:simulateNetworkConditions({
      latency = 1000,
      latencyDeviation = 100,
      packetLossChance = 0.00
    })
    network.clients[2]:connect()
  end
end

function love.update(dt)
  if network.clients[1] then
    network.clients[1]:setInputs({
      up = love.keyboard.isDown('w'),
      left = love.keyboard.isDown('a'),
      down = love.keyboard.isDown('s'),
      right = love.keyboard.isDown('d')
    })
  end
  if network.clients[2] then
    network.clients[2]:setInputs({
      up = love.keyboard.isDown('up'),
      left = love.keyboard.isDown('left'),
      down = love.keyboard.isDown('down'),
      right = love.keyboard.isDown('right')
    })
  end
  -- Update the network
  network:update(dt)
end

function love.draw()
  -- Draw the server and the clients
  if network:isServerSide() then
    drawSimulation(network.server:getSimulation(), nil, 160, 10, 300, 300, true, 'SERVER')
  end
  if network:isClientSide() then
    if network.clients[1] then
      drawSimulation(network.clients[1]:getSimulationWithoutPrediction(), nil, 160, 10, 300, 300, false)
      drawSimulation(network.clients[1]:getSimulation(), network.clients[1], 10, 320, 300, 300, true, 'CLIENT 1 - WASD')
      drawSimulation(network.clients[1]:getSimulationWithoutPrediction(), network.clients[1], 10, 320, 300, 300, false)
    end
    if network.clients[2] then
      drawSimulation(network.clients[2]:getSimulationWithoutPrediction(), nil, 160, 10, 300, 300, false)
      drawSimulation(network.clients[2]:getSimulation(), network.clients[2], 320, 320, 300, 300, true, 'CLIENT 2 - ARROW KEYS')
      drawSimulation(network.clients[2]:getSimulationWithoutPrediction(), network.clients[2], 320, 320, 300, 300, false)
    end
  end
end

function love.keypressed(key)
  if key == 'lshift' and network.clients[1] then
    network.clients[1]:fireEvent('change-player-color', {
      clientId = network.clients[1].clientId,
      color = { math.random(), math.random(), math.random() }
    })
  elseif key == 'rshift' and network.clients[2] then
    network.clients[2]:fireEvent('change-player-color', {
      clientId = network.clients[2].clientId,
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
      love.graphics.print('status: ' .. (client:isConnected() and 'connected' or (client:isConnecting() and 'connecting' or 'disconnected')), x + 4, y + 34)
      love.graphics.print('client id: ' .. (client.clientId or '--'), x + 4, y + 50)
      love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 66)
    end
  end
end
