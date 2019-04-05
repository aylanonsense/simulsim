local Simulation = require 'src/simulation/Simulation'
local createFauxSimulationNetwork = require 'src/simulationNetwork/createFauxSimulationNetwork'

function defineSimulation(params)
  return Simulation:define(params)
end

function createNetworkedSimulation(params)
  local server, clients, transportLayers = createFauxSimulationNetwork(params)

  -- Create a new network
  return {
    -- Public vars
    server = server,
    client = clients[1],
    clients = clients,

    -- Private vars
    _transportLayers = transportLayers,

    -- Public methods
    update = function(self, dt)
      self.server:update(dt)
      for _, client in ipairs(self.clients) do
        client:update(dt)
      end
      for _, transportLayer in ipairs(self._transportLayers) do
        transportLayer:update(dt)
      end
    end
  }
end

return {
  defineSimulation = defineSimulation,
  createNetworkedSimulation = createNetworkedSimulation
}
