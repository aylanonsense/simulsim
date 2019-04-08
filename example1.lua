-- Load dependencies
local simulsim = require 'simulsim'

-- Create a new game simulation
local simulationDefinition = simulsim.defineSimulation({
  initialState = {
    data = {
      backgroundColor = { 1, 1, 1 }
    }
  },
  handleEvent = function(self, eventType, eventData)
    if eventType == 'change-background-color' then
      self.data.backgroundColor = eventData.backgroundColor
    end
  end
})

-- Game params
local network
local timeUntilChangeColor

function love.load()
  timeUntilChangeColor = 0.0
  -- Create a new network
  network = simulsim.createNetworkedSimulation({
    simulationDefinition = simulationDefinition,
    numClients = 2
  })
  -- Start the network
  network.server:startListening()
  network.clients[1]:simulateNetworkConditions({
    latency = 100,
    latencyDeviation = 5,
    packetLossChance = 0.01
  })
  network.clients[1]:connect()
  network.clients[2]:simulateNetworkConditions({
    latency = 1000,
    latencyDeviation = 50,
    packetLossChance = 0.01
  })
  network.clients[2]:connect()
  -- Make the text bigger
  love.graphics.setFont(love.graphics.newFont(20))
end

function love.update(dt)
  -- Possibly change the background color
  timeUntilChangeColor = timeUntilChangeColor - dt
  if timeUntilChangeColor < 0.00 then
    timeUntilChangeColor = 1.5
    network.server:fireEvent('change-background-color', {
      backgroundColor = { math.random(), math.random(), math.random() }
    })
  end
  -- Update the network
  network:update(dt)
end

function love.draw()
  -- Draw the server and the clients
  drawSimulation(network.server:getSimulation(), nil, 110, 10, 200, 150)
  drawSimulation(network.clients[1]:getSimulation(), network.clients[1], 10, 170, 200, 150)
  drawSimulation(network.clients[2]:getSimulation(), network.clients[2], 220, 170, 200, 150)
end

function drawSimulation(sim, client, x, y, width, height)
  love.graphics.setColor(sim.data.backgroundColor)
  love.graphics.rectangle('fill', x, y, width, height)
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle('fill', x, y, width, 58)
  -- Draw network info
  love.graphics.setColor(0, 0, 0)
  love.graphics.print('sim time: ' .. math.floor(sim.frame / 60), x + 4, y + 4)
  if client then
    love.graphics.print('latency: ' .. client:getFramesOfLatency() .. ' frames', x + 4, y + 30)
  end
end
