-- Load dependencies
local simulsim = require 'simulsim'

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

function love.load()
  -- Create a new network
  network = simulsim.createNetworkedSimulation({
    simulationDefinition = simulationDefinition,
    numClients = 2
  })
  -- Start the network
  network.server:startListening()
  network.server:onConnect(function(client)
    network.server:fireEvent('spawn-player-entity', {
      clientId = client.clientId,
      x = math.random(10, 170),
      y = math.random(60, 170),
      color = { math.random(), math.random(), math.random() }
    })
  end)
  network.clients[1]:simulateNetworkConditions({
    latency = 100,
    latencyDeviation = 5,
    packetLossChance = 0.0
  })
  network.clients[1]:connect()
  network.clients[2]:simulateNetworkConditions({
    latency = 1000,
    latencyDeviation = 50,
    packetLossChance = 0.0
  })
  network.clients[2]:connect()
end

function love.update(dt)
  network.clients[1]:setInputs({
    up = love.keyboard.isDown('w'),
    left = love.keyboard.isDown('a'),
    down = love.keyboard.isDown('s'),
    right = love.keyboard.isDown('d')
  })
  network.clients[2]:setInputs({
    up = love.keyboard.isDown('up'),
    left = love.keyboard.isDown('left'),
    down = love.keyboard.isDown('down'),
    right = love.keyboard.isDown('right')
  })
  -- Update the network
  network:update(dt)
end

function love.draw()
  -- Draw the server and the clients
  drawSimulation(network.server:getSimulation(), nil, 110, 10, 200, 200)
  drawSimulation(network.clients[1]:getSimulation(), network.clients[1], 10, 220, 200, 200)
  drawSimulation(network.clients[2]:getSimulation(), network.clients[2], 220, 220, 200, 200)
end

function love.keypressed(key)
  if key == 'lshift' then
    network.clients[1]:fireEvent('change-player-color', {
      clientId = network.clients[1].clientId,
      color = { math.random(), math.random(), math.random() }
    })
  elseif key == 'rshift' then
    network.clients[2]:fireEvent('change-player-color', {
      clientId = network.clients[2].clientId,
      color = { math.random(), math.random(), math.random() }
    })
  end
end

function drawSimulation(sim, client, x, y, width, height)
  love.graphics.setColor(0.5, 0.5, 0.5)
  love.graphics.rectangle('fill', x, y, width, height)
  -- Draw entities
  for _, entity in ipairs(sim.entities) do
    love.graphics.setColor(entity.color)
    love.graphics.rectangle('fill', x + entity.x, y + entity.y, entity.width, entity.height)
    love.graphics.setColor(0, 0, 0)
    love.graphics.print(entity.clientId, x + entity.x + 6, y + entity.y + 4)
  end
  -- Draw network info
  love.graphics.setColor(0, 0, 0)
  love.graphics.print('sim time: ' .. math.floor(sim.frame / 60), x + 4, y + 2)
  if client then
    love.graphics.print('client id: ' .. (client.clientId or '--'), x + 4, y + 18)
    love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 34)
  end
end
