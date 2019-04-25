local share = require 'src/lib/share'
local Simulation = require 'src/simulation/Simulation'
local createLocalSimulationNetwork = require 'src/simulationNetwork/createLocalSimulationNetwork'
local createShareSimulationNetwork = require 'src/simulationNetwork/createShareSimulationNetwork'

function defineSimulation(params)
  return Simulation:define(params)
end

function createNetworkedSimulation(params)
  params = params or {}
  local useFakeNetwork = params.useFakeNetwork

  if useFakeNetwork then
    local server, clients, transportStreams = createLocalSimulationNetwork(params)
    -- Create a new network
    return {
      -- Public vars
      server = server,
      client = clients[1],
      clients = clients,

      -- Private vars
      _transportStreams = transportStreams,

      -- Public methods
      update = function(self, dt)
        self.server:update(dt)
        for _, client in ipairs(self.clients) do
          client:update(dt)
        end
        for _, transportStream in ipairs(self._transportStreams) do
          transportStream:update(dt)
        end
      end
    }
  else
    local server, client = createShareSimulationNetwork(params)
    return {
      -- Public vars
      server = server,
      client = client,
      clients = { client },

      -- Public methods
      update = function(self, dt)
        self.server:update(dt)
        self.client:update(dt)
        share.update(dt)
      end
    }
  end
end

return {
  defineSimulation = defineSimulation,
  createNetworkedSimulation = createNetworkedSimulation
}
