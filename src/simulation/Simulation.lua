local tableHelpers = require 'src/helper/table'

local Simulation = {}
function Simulation:new(params)
  local initialState = params and params.initialState

  local sim = {
    -- Public vars
    time = 0.00,
    frame = 0,
    nextEntityId = 1,
    data = {},
    entities = {},

    -- Public methods
    -- Gets the current state of the simulation as a simple table
    getState = function(self)
      local state = {
        time = self.time,
        frame = self.frame,
        nextEntityId = self.nextEntityId,
        data = tableHelpers.cloneTable(self.data),
        entities = {}
      }
      for _, entity in ipairs(self.entities) do
        table.insert(state.entities, tableHelpers.cloneTable(self:_getStateFromEntity(entity)))
      end
      return state
    end,
    -- Sets the current state of the simulation
    setState = function(self, state)
      self.time = state.time
      self.frame = state.frame
      self.nextEntityId = state.nextEntityId
      self.data = tableHelpers.cloneTable(state.data)
      self.entities = {}
      for _, entityState in ipairs(state.entities) do
        table.insert(self.entities, self:_createEntityFromState(tableHelpers.cloneTable(entityState)))
      end
    end,
    -- Creates another simulation identical to this one
    clone = function(self)
      -- Create a new simulation
      local clonedSim = Simulation:new()
      -- Copy all the functions that may have been overridden
      for k, v in pairs(self) do
        if type(v) == 'function' then
          clonedSim[k] = v
        end
      end
      -- Set the new simuation's state
      clonedSim:setState(self:getState())
      -- Return the newly-cloned simulation
      return clonedSim
    end,
    -- Gets an entity with the given id
    getEntityById = function(self, entityId)
      for _, entity in ipairs(self.entities) do
        if self:_getEntityId(entity) == entityId then
          return entity
        end
      end
    end,
    -- Spawns a new entity, generating a new id for it
    spawnEntity = function(self, entity, skipIdGeneration)
      table.insert(self.entities, entity)
      if not skipIdGeneration then
        self:_setEntityId(entity, self:_generateEntityId())
      end
      return entity
    end,
    -- Despawns an entity with the given id and returns the removed entity
    despawnEntity = function(self, entityId)
      for i = #self.entities, 1, -1 do
        local entity = self.entities[i]
        if self:_getEntityId(entity) == entityId then
          table.remove(self.entities, i)
          return entity
        end
      end
    end,

    -- Private methods
    -- Generates a new entity id
    _generateEntityId = function(self)
      local entityId = self.nextEntityId
      self.nextEntityId = self.nextEntityId + 1
      return entityId
    end,
    -- Gets the unique id from a fully-hydrated entity object
    _getEntityId = function(self, entity)
      return entity.id
    end,
    -- Sets the unique id on a fully-hydrated entity object
    _setEntityId = function(self, entity, entityId)
      entity.id = entityId
    end,
    -- Transforms a fully-hydrated entity (with methods, etc) into a simple state object
    _getStateFromEntity = function(self, entity)
      return entity
    end,
    -- Transforms a simple state object into a fully-hydrated entity
    _createEntityFromState = function(self, state)
      return state
    end,

    -- Methods to override
    update = function(self, dt, inputs, events, isTopFrame) end
  }

  -- Set the simulation's initial state
  if initialState then
    sim:setState(initialState)
  end

  -- Return the new simulation
  return sim
end

return Simulation
