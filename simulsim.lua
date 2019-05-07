local Game = require 'src/game/Game'
local createGameNetwork = require 'src/network/createGameNetwork'
local createPublicAPI = require 'src/api/createPublicAPI'

function defineGame(params)
  return Game:define(params)
end

function createGameNetwork2(params)
  return createPublicAPI(createGameNetwork(params))
end

return {
  defineGame = defineGame,
  createGameNetwork = createGameNetwork2
}
