local Simulation = require 'src/simulation/Simulation'
local createNetwork = require 'src/simulationNetwork/createNetwork'

function defineSimulation(params)
  return Simulation:define(params)
end

return {
  defineSimulation = defineSimulation,
  createNetwork = createNetwork
}
