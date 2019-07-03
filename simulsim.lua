local Game = require 'src/game/Game'
local createGameNetwork = require 'src/network/createGameNetwork'
local createPublicAPI = require 'src/api/createPublicAPI'
local logger = require 'src/utils/logger'
local stringUtils = require 'src/utils/string'
local tableUtils = require 'src/utils/table'

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
  setLogLevel = setLogLevel,
  utils = {
    stringify = stringUtils.stringify,
    generateRandomString = stringUtils.generateRandomString,
    cloneTable = tableUtils.cloneTable,
    clearProps = tableUtils.clearProps,
    copyProps = tableUtils.copyProps,
    isEquivalent = tableUtils.isEquivalent
  }
}
