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
    latency = 50,
    latencyDeviation = 5,
    packetLossChance = 0.05
  })
  network.clients[1]:connect()
  network.clients[2]:simulateNetworkConditions({
    latency = 500,
    latencyDeviation = 50,
    packetLossChance = 0.05
  })
  network.clients[2]:connect()
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
  drawSimulation(network.server:getSimulation(), 110, 10, 200, 200)
  drawSimulation(network.clients[1]:getSimulation(), 10, 220, 200, 200)
  drawSimulation(network.clients[2]:getSimulation(), 220, 220, 200, 200)
end

function drawSimulation(sim, x, y, width, height)
  love.graphics.setColor(sim.data.backgroundColor)
  love.graphics.rectangle('fill', x, y, width, height)
end
