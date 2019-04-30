local tableUtils = require 'src/utils/table'

-- Useful no-op method
function noop() end

local Simulation = {}
function Simulation:new(params)
  params = params or {}
  local initialState = params.initialState

  local simulation = {
    -- Private vars
    _initialState = initialState,
    _entityIdPrefix = '',
    _nextEntityId = 1,

    -- Public vars
    frame = 0,
    inputs = {},
    data = {},
    entities = {},

    -- Public methods
    -- Gets the current state of the simulation as a simple table
    getState = function(self)
      local state = {
        frame = self.frame,
        inputs = tableUtils.cloneTable(self.inputs),
        data = tableUtils.cloneTable(self.data),
        entities = {}
      }
      for _, entity in ipairs(self.entities) do
        table.insert(state.entities, tableUtils.cloneTable(self:getStateFromEntity(entity)))
      end
      return state
    end,
    -- Sets the current state of the simulation
    setState = function(self, state)
      self.frame = state.frame or self.frame
      if state.inputs then
        self.inputs = tableUtils.cloneTable(state.inputs)
      end
      if state.data then
        self.data = tableUtils.cloneTable(state.data)
      end
      if state.entities then
        self.entities = {}
        for _, entityState in ipairs(state.entities) do
          table.insert(self.entities, self:createEntityFromState(tableUtils.cloneTable(entityState)))
        end
      end
    end,
    -- Creates another simulation identical to this one
    clone = function(self)
      -- Create a new simulation
      local clonedSimulation = Simulation:new()
      -- Copy all overrideable methods
      clonedSimulation.update = self.update
      clonedSimulation.handleEvent = self.handleEvent
      -- Set the new simuation's state
      clonedSimulation:setState(self:getState())
      -- Set the simulation's private vars
      clonedSimulation._entityIdPrefix = self._entityIdPrefix
      clonedSimulation._nextEntityId = self._nextEntityId
      -- Return the newly-cloned simulation
      return clonedSimulation
    end,
    -- Gets an entity with the given id
    getEntityById = function(self, entityId)
      for _, entity in ipairs(self.entities) do
        if self:getEntityId(entity) == entityId then
          return entity
        end
      end
    end,
    -- Spawns a new entity, generating a new id for it
    spawnEntity = function(self, entity, shouldGenerateId)
      -- generate an id for the entity if it doesn't already have one
      if shouldGenerateId == nil then
        shouldGenerateId = not self:getEntityId(entity)
      end
      if shouldGenerateId then
        self:setEntityId(entity, self:generateEntityId())
      end
      -- Add the entity to the simulation
      table.insert(self.entities, entity)
      return entity
    end,
    -- Despawns an entity with the given id and returns the removed entity
    despawnEntity = function(self, entityId)
      for i = #self.entities, 1, -1 do
        local entity = self.entities[i]
        if self:getEntityId(entity) == entityId then
          table.remove(self.entities, i)
          return entity
        end
      end
    end,
    resetEntityIdGeneration = function(self, prefix)
      self._entityIdPrefix = prefix or ''
      self._nextEntityId = 1
    end,
    reset = function(self)
      self:resetEntityIdGeneration()
      self.frame = 0
      self.inputs = {}
      self.data = {}
      self.entities = {}
      if self._initialState then
        self:setState(self._initialState)
      end
    end,
    getClientInputs = function(self, clientId)
      return self.inputs[clientId]
    end,
    -- Generates a new entity id
    generateEntityId = function(self)
      local entityId = self._entityIdPrefix .. self._nextEntityId
      self._nextEntityId = self._nextEntityId + 1
      return entityId
    end,
    -- Gets the unique id from a fully-hydrated entity object
    getEntityId = function(self, entity)
      return entity.id
    end,
    -- Sets the unique id on a fully-hydrated entity object
    setEntityId = function(self, entity, entityId)
      entity.id = entityId
    end,
    -- Transforms a fully-hydrated entity (with methods, etc) into a simple state object
    getStateFromEntity = function(self, entity)
      return entity
    end,
    -- Transforms a simple state object into a fully-hydrated entity
    createEntityFromState = function(self, state)
      return state
    end,

    -- Methods to override
    update = function(self, dt, inputs, events, isTopFrame) end,
    handleEvent = function(self, eventType, eventData) end
  }

  -- Set the simulation's initial state
  if initialState then
    simulation:setState(initialState)
  end

  -- Return the new simulation
  return simulation
end
function Simulation:define(params)
  params = params or {}
  local initialState = params.initialState
  local update = params.update or noop
  local handleEvent = params.handleEvent or noop

  return {
    new = function(params)
      params = params or {}
      params.initialState = params.initialState or initialState
      -- Create a new simulation
      local simulation = Simulation:new(params)
      -- Override the overridable methods
      simulation.update = update
      simulation.handleEvent = handleEvent
      -- Return the new simulation
      return simulation
    end
  }
end

return Simulation
