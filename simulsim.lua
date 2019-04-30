local Simulation = require 'src/simulation/Simulation'
local createNetwork = require 'src/simulationNetwork/createNetwork'
local createPublicAPI = require 'src/simulationNetwork/createPublicAPI'

function defineGame(params)
  return Simulation:define(params)
end

function createGameNetwork(params)
  params = params or {}
  params.simulationDefinition = params.gameDefinition
  return createPublicAPI(createNetwork(params))
end

return {
  defineGame = defineGame,
  createGameNetwork = createGameNetwork
}
