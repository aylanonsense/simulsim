local Simulation = require 'src/game/Game'
local createNetwork = require 'src/network/createNetwork'
local createPublicAPI = require 'src/api/createPublicAPI'

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
