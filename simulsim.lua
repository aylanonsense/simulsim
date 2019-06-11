local Game = require 'src/game/Game'
local createGameNetwork = require 'src/network/createGameNetwork'
local createPublicAPI = require 'src/api/createPublicAPI'
local logger = require 'src/utils/logger'

local function defineGame(params)
  return Game:define(params)
end

local function createGameNetworkAPI(gameDefinition, params)
  return createPublicAPI(createGameNetwork(gameDefinition, params), params)
end

local function setLogLevel(lvl)
  logger.setLogLevel(lvl)
end

return {
  defineGame = defineGame,
  createGameNetwork = createGameNetworkAPI,
  setLogLevel = setLogLevel
}
