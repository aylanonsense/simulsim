local tableUtils = require 'src/utils/table'

-- Useful no-op method
function noop() end

local Game = {}
function Game:new(params)
  params = params or {}
  local initialState = params.initialState

  local game = {
    -- Private vars
    _entityIdPrefix = '',
    _nextEntityId = 1,

    -- Public vars
    frame = 0,
    entities = {},
    data = {},
    inputs = {},
    events = {},

    -- Public methods
    -- Gets the current state of the game as a simple table
    getState = function(self)
      local state = {
        frame = self.frame,
        entities = {},
        data = tableUtils.cloneTable(self.data),
        inputs = tableUtils.cloneTable(self.inputs)
      }
      for _, entity in ipairs(self.entities) do
        table.insert(state.entities, tableUtils.cloneTable(self:serializeEntity(entity)))
      end
      return state
    end,
    -- Sets the current state of the game
    setState = function(self, state)
      self.frame = state.frame or self.frame
      if state.entities then
        self.entities = {}
        for _, entityState in ipairs(state.entities) do
          table.insert(self.entities, self:deserializeEntity(tableUtils.cloneTable(entityState)))
        end
      end
      if state.data then
        self.data = tableUtils.cloneTable(state.data)
      end
      if state.inputs then
        self.inputs = tableUtils.cloneTable(state.inputs)
      end
    end,
    -- Creates another game identical to this one
    clone = function(self)
      -- Create a new game
      local clonedGame = Game:new()
      -- Copy all properties and methods
      for k, v in pairs(self) do
        clonedGame[k] = v
      end
      clonedGame.events = tableUtils.cloneTable(self.events)
      -- Set the new game's state
      clonedGame:setState(self:getState())
      -- Return the newly-cloned game
      return clonedGame
    end,
    getInputsForClient = function(self, clientId)
      return self.inputs[clientId]
    end,
    -- Gets an entity with the given id
    getEntityById = function(self, entityId)
      for index, entity in ipairs(self.entities) do
        if self:getEntityId(entity) == entityId then
          return entity, index
        end
      end
    end,
    getEntityWhere = function(self, criteria)
      for index, entity in ipairs(self.entities) do
        local isMatch
        if type(criteria) == 'function' then
          isMatch = criteria(entity)
        else
          isMatch = true
          for k, v in pairs(criteria) do
            if entity[k] ~= v then
              isMatch = false
              break
            end
          end
        end
        if isMatch then
          return entity, index
        end
      end
    end,
    getEntities = function(self)
      return self.entities
    end,
    getEntitiesWhere = function(self, criteria)
      local matchingEntities = {}
      for index, entity in ipairs(self.entities) do
        local isMatch
        if type(criteria) == 'function' then
          isMatch = criteria(entity)
        else
          isMatch = true
          for k, v in pairs(criteria) do
            if entity[k] ~= v then
              isMatch = false
              break
            end
          end
        end
        if isMatch then
          table.insert(matchingEntities, entity)
        end
      end
      return matchingEntities
    end,
    forEachEntity = function(self, callback)
      for _, entity in ipairs(self.entities) do
        callback(entity)
      end
    end,
    forEachEntityWhere = function(self, criteria, callback)
      for index, entity in ipairs(self.entities) do
        local isMatch
        if type(criteria) == 'function' then
          isMatch = criteria(entity)
        else
          isMatch = true
          for k, v in pairs(criteria) do
            if entity[k] ~= v then
              isMatch = false
              break
            end
          end
        end
        if isMatch then
          callback(entity)
        end
      end
    end,
    -- Spawns a new entity, generating a new id for it
    spawnEntity = function(self, entity, params)
      params = params or {}
      local shouldGenerateId
      if params.shouldGenerateId ~= nil then
        shouldGenerateId = params.shouldGenerateId
      else
        shouldGenerateId = not self:getEntityId(entity)
      end
      -- generate an id for the entity if it doesn't already have one
      if shouldGenerateId then
        self:setEntityId(entity, self:generateEntityId())
      end
      -- Add the entity to the game
      table.insert(self.entities, entity)
      return entity
    end,
    -- Despawns an entity
    despawnEntity = function(self, entity)
      if entity then
        local id = self:getEntityId(entity)
        for i = #self.entities, 1, -1 do
          if self:getEntityId(self.entities[i]) == id then
            table.remove(self.entities, i)
            return entity
          end
        end
      end
    end,
    reset = function(self)
      self:resetEntityIdGeneration()
      self.frame = 0
      self.entities = {}
      self.data = {}
      self.inputs = {}
      self.events = {}
    end,
    resetEntityIdGeneration = function(self, prefix)
      self._entityIdPrefix = prefix or ''
      self._nextEntityId = 1
    end,
    -- Gets the unique id from a fully-hydrated entity object
    getEntityId = function(self, entity)
      return entity.id
    end,
    -- Sets the unique id on a fully-hydrated entity object
    setEntityId = function(self, entity, entityId)
      entity.id = entityId
    end,
    -- Generates a new entity id
    generateEntityId = function(self)
      local entityId = self._entityIdPrefix .. self._nextEntityId
      self._nextEntityId = self._nextEntityId + 1
      return entityId
    end,
    -- Transforms a fully-hydrated entity (with methods, etc) into a simple state object
    serializeEntity = function(self, entity)
      return entity
    end,
    -- Transforms a simple state object into a fully-hydrated entity
    deserializeEntity = function(self, state)
      return tableUtils.cloneTable(state)
    end,
    isSyncEnabledForEntity = function(self, entity)
      if entity._metadata then
        if entity._metadata.sync == false then
          return false
        elseif entity._metadata.syncDisabledFrames and entity._metadata.syncDisabledFrames > 0 then
          return false
        end
      end
      return true
    end,
    enableSyncForEntity = function(self, entity)
      if not entity._metadata then
        entity._metadata = {}
      end
      entity._metadata.sync = nil
    end,
    disableSyncForEntity = function(self, entity)
      if not entity._metadata then
        entity._metadata = {}
      end
      entity._metadata.sync = false
    end,
    temporarilyDisableSyncForEntity = function(self, entity)
      if not entity._metadata then
        entity._metadata = {}
      end
      entity._metadata.syncDisabledFrames = 150 -- TODO calculate an actual number
    end,
    updateEntityMetadata = function(self, dt)
      for _, entity in ipairs(self.entities) do
        if entity._metadata and entity._metadata.syncDisabledFrames and entity._metadata.syncDisabledFrames > 0 then
          entity._metadata.syncDisabledFrames = entity._metadata.syncDisabledFrames - 1
          if entity._metadata.syncDisabledFrames <= 0 then
            entity._metadata.syncDisabledFrames = nil
          end
        end
      end
    end,

    -- Methods to override
    update = function(self, dt, isRenderable) end,
    handleEvent = function(self, eventType, eventData, isRenderable) end
  }

  if initialState then
    game:setState(initialState)
  end

  -- Return the new game
  return game
end
function Game:define(params)
  params = params or {}

  -- Create a new game definition
  local GameDefinition = {}
  -- Plop all the params onto it
  for k, v in pairs(params) do
    GameDefinition[k] = v
  end
  -- Add a method for instantiating a game from this game definition
  function GameDefinition:new(params)
    -- Create a new game
    local game = Game:new(params)
    -- Add/override methods/properties
    for k, v in pairs(GameDefinition) do
      if k ~= 'new' then
        game[k] = v
      end
    end
    -- Return the new game
    return game
  end
  -- Return the new game definition
  return GameDefinition
end

return Game
