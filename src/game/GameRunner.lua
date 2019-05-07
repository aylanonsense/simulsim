local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'

local GameRunner = {}
function GameRunner:new(params)
  params = params or {}
  local simulation = params.simulation
  local framesOfHistory = params.framesOfHistory or 30
  local framesBetweenStateSnapshots = params.framesBetweenStateSnapshots or 5

  return {
    -- Private config vars
    _framesBetweenStateSnapshots = framesBetweenStateSnapshots,

    -- Private vars
    _simulation = simulation,
    _futureStates = {},
    _transformHistory = {},
    _stateHistory = {},
    _eventHistory = {},

    -- Public vars
    framesOfHistory = framesOfHistory,

    -- Public methods
    getSimulation = function(self)
      return self._simulation
    end,
    -- Adds an event to be applied on the given frame, which may trigger a rewind
    applyEvent = function(self, event, params)
      params = params or {}
      local preserveFrame = params.preserveFrame
      local framesUntilAutoUnapply = params.framesUntilAutoUnapply
      -- If the event occurred too far in the past, there's not much we can do about it
      local maxAllowedAge = self.framesOfHistory
      if framesUntilAutoUnapply and framesUntilAutoUnapply < maxAllowedAge then
        maxAllowedAge = framesUntilAutoUnapply
      end
      if event.frame < self._simulation.frame - maxAllowedAge then
        return false
      -- If the event takes place in the past, regenerate the state history
      else
        local frameToRegenerateFrom = event.frame
        -- Create a wrapper for the event with extra metadata
        local record = {
          event = event,
          preserveFrame = preserveFrame
        }
        if framesUntilAutoUnapply then
          record.autoUnapplyFrame = event.frame + framesUntilAutoUnapply
        end
        -- See if there already exists an event with that id
        local replacedEvent = false
        for i = #self._eventHistory, 1, -1 do
          if self._eventHistory[i].event.id == event.id then
            if self._eventHistory[i].event.frame < frameToRegenerateFrom then
              frameToRegenerateFrom = self._eventHistory[i].event.frame
            end
            if self._eventHistory[i].preserveFrame then
              record.event = tableUtils.cloneTable(record.event)
              record.event.frame = self._eventHistory[i].event.frame
            end
            self._eventHistory[i] = record
            replacedEvent = true
            break
          end
        end
        -- Otherwise just insert it
        if not replacedEvent then
          table.insert(self._eventHistory, record)
        end
        -- And regenerate states that are now invalid
        if frameToRegenerateFrom <= self._simulation.frame then
          return self:_regenerateStateHistoryOnOrAfterFrame(frameToRegenerateFrom)
        else
          return true
        end
      end
    end,
    -- Cancels an event that was applied prior
    unapplyEvent = function(self, eventId)
      -- Search for the event
      for i = #self._eventHistory, 1, -1 do
        local event = self._eventHistory[i].event
        if event.id == eventId then
          -- Remove the event
          table.remove(self._eventHistory, i)
          -- Regenerate state history if the event was applied in the past
          if event.frame <= self._simulation.frame then
            self:_regenerateStateHistoryOnOrAfterFrame(event.frame)
          end
          return true
        end
      end
      return false
    end,
    -- Sets the current state of the simulation, removing all past history in the process
    setState = function(self, state)
      -- Set the simulation's state
      self._simulation:setState(state)
      -- Only future events are still valid
      for i = #self._eventHistory, 1, -1 do
        if self._eventHistory[i].event.frame <= self._simulation.frame then
          table.remove(self._eventHistory, i)
        end
      end
      -- The only valid state is the current one
      self._stateHistory = {}
      self:_generateStateSnapshot()
    end,
    -- Sets the state, or applies it to the past if the state is in the past, or schedules it to be applied in the future
    applyState = function(self, state)
      -- If the state represents a moment in the past, rewind to apply it
      if state.frame <= self._simulation.frame then
        local currFrame = self._simulation.frame
        if self:_rewindToFrame(state.frame) then
          self:setState(state)
          self:_fastForwardToFrame(currFrame, true)
          return true
        else
          return false
        end
      -- Otherwise if the state represents a moment in the future, schedule it
      else
        table.insert(self._futureStates, state)
        return true
      end
    end,
    applyStateTransform = function(self, frame, transformFunc)
      table.insert(self._transformHistory, { frame = frame, transform = transformFunc })
      -- If this is a moment in the past, rewind to apply it
      if frame <= self._simulation.frame then
        local currFrame = self._simulation.frame
        if self:_rewindToFrame(frame) then
          transformFunc(self._simulation)
          self:_invalidateStateHistoryOnOrAfterFrame(self._simulation.frame)
          self:_generateStateSnapshot()
          self:_fastForwardToFrame(currFrame, true)
          return true
        else
          return false
        end
      -- Otherwise, it's scheduled to happen
      else
        return true
      end
    end,
    moveForwardOneFrame = function(self, dt)
      self:_moveSimulationForwardOneFrame(dt, true, true)
      self:_removeOldHistory()
      self:_autoUnapplyEvents()
    end,
    reset = function(self)
      self._simulation:reset()
      self._futureStates = {}
      self._transformHistory = {}
      self._stateHistory = {}
      self._eventHistory = {}
    end,
    rewind = function(self, numFrames)
      if self:_rewindToFrame(self._simulation.frame - numFrames) then
        self:_invalidateStateHistoryOnOrAfterFrame(self._simulation.frame + 1)
        return true
      else
        return false
      end
    end,
    fastForward = function(self, numFrames)
      self:_fastForwardToFrame(self._simulation.frame + numFrames, true)
      return true
    end,
    clone = function(self)
      -- Create a new runner
      local clonedRunner = GameRunner:new({
        simulation = self._simulation:clone(),
        framesOfHistory = self.framesOfHistory,
        framesBetweenStateSnapshots = self._framesBetweenStateSnapshots
      })
      -- Set the runner's private vars
      clonedRunner._futureStates = tableUtils.cloneTable(self._futureStates)
      clonedRunner._transformHistory = tableUtils.cloneTable(self._transformHistory)
      clonedRunner._stateHistory = tableUtils.cloneTable(self._stateHistory)
      clonedRunner._eventHistory = tableUtils.cloneTable(self._eventHistory)
      -- Return the newly-cloned runner
      return clonedRunner
    end,

    -- Private methods
    -- Set the simulation to the state it was in after the given frame
    _rewindToFrame = function(self, frame)
      -- Get a state from before or on the given frame
      local mostRecentState = nil
      for _, state in ipairs(self._stateHistory) do
        if state.frame <= frame and (mostRecentState == nil or mostRecentState.frame < state.frame) then
          mostRecentState = state
        end
      end
      if mostRecentState then
        -- Set the simulation to that state
        self._simulation:setState(mostRecentState)
        -- Then fast forwad to the correct frame
        self:_fastForwardToFrame(frame, false)
        return true
      else
        -- The rewind could not occur
        return false
      end
    end,
    -- Fast forwards the simulation to the given frame
    _fastForwardToFrame = function(self, frame, shouldGenerateStateSnapshots)
      while self._simulation.frame < frame do
        self:_moveSimulationForwardOneFrame(1 / 60, false, shouldGenerateStateSnapshots)
      end
    end,
    -- Generates a state snapshot and adds it to the state history
    _generateStateSnapshot = function(self)
      table.insert(self._stateHistory, self._simulation:getState())
    end,
    -- Remove all state snapshots after the given frame
    _invalidateStateHistoryOnOrAfterFrame = function(self, frame)
      for i = #self._stateHistory, 1, -1 do
        if self._stateHistory[i].frame >= frame then
          table.remove(self._stateHistory, i)
        end
      end
    end,
    -- Invalidates and then regenerates all the state history after the given frame
    _regenerateStateHistoryOnOrAfterFrame = function(self, frame)
      local currFrame = self._simulation.frame
      -- Rewind to just before that frame
      if self:_rewindToFrame(frame - 1) then
        -- All the state snapshots on or after the given frame are invalid now
        self:_invalidateStateHistoryOnOrAfterFrame(frame)
        -- Then play back to the frame we were just at, generating state history as we go
        self:_fastForwardToFrame(currFrame, true)
        return true
      else
        return false
      end
    end,
    -- Advances the simulation forward one frame
    _moveSimulationForwardOneFrame = function(self, dt, isTopFrame, shouldGenerateStateSnapshots)
      -- Advance the simulation's time
      self._simulation.frame = self._simulation.frame + 1
      -- Get the events that take place on this frame
      local events = self:_getEventsAtFrame(self._simulation.frame)
      -- Input-related events are automatically applied to the simulation's inputs
      local nonInputEvents = {}
      for _, event in ipairs(events) do
        if event.isInputEvent and event.type == 'set-inputs' then
          self._simulation.inputs[event.data.clientId] = event.data.inputs
        else
          table.insert(nonInputEvents, event)
          self._simulation:resetEntityIdGeneration('event-' .. event.id .. '-')
          self._simulation:handleEvent(event.type, event.data)
        end
      end
      -- Update the simulation
      self._simulation:resetEntityIdGeneration('frame-' .. self._simulation.frame .. '-')
      self._simulation:updateMetadata(dt)
      self._simulation:update(dt, self._simulation.inputs, nonInputEvents, isTopFrame)
      -- Check to see if any scheduled states need to applied now
      for i = #self._futureStates, 1, -1 do
        if self._futureStates[i].frame == self._simulation.frame then
          self:setState(self._futureStates[i])
        end
        if self._futureStates[i].frame <= self._simulation.frame then
          table.remove(self._futureStates, i)
        end
      end
      -- Check to see if any scheduled transformations need to applied now
      for i = #self._transformHistory, 1, -1 do
        if self._transformHistory[i].frame == self._simulation.frame then
          self._transformHistory[i].transform(self._simulation)
        end
      end
      -- Generate a snapshot of the state every so often
      if shouldGenerateStateSnapshots and self._simulation.frame % self._framesBetweenStateSnapshots == 0 then
        self:_generateStateSnapshot()
      end
    end,
    -- Get all events that occurred at the given frame
    _getEventsAtFrame = function(self, frame)
      local events = {}
      for _, record in ipairs(self._eventHistory) do
        if record.event.frame == frame then
          table.insert(events, record.event)
        end
      end
      return events
    end,
    -- Removes any state snapshots and events that are beyond the history threshold
    _removeOldHistory = function(self)
      -- Remove old state history
      for i = #self._stateHistory, 1, -1 do
        if self._stateHistory[i].frame < self._simulation.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._stateHistory, i)
        end
      end
      -- Remove old transformation history
      for i = #self._transformHistory, 1, -1 do
        if self._transformHistory[i].frame < self._simulation.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._transformHistory, i)
        end
      end
      -- Remove old event history
      for i = #self._eventHistory, 1, -1 do
        if self._eventHistory[i].event.frame < self._simulation.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._eventHistory, i)
        end
      end
    end,
    -- Remove any events that should be automatically unapplied
    _autoUnapplyEvents = function(self)
      -- Find any events that need to be automatically unapplied
      local frameToRegenerateFrom = nil
      for i = #self._eventHistory, 1, -1 do
        local record = self._eventHistory[i]
        if record.autoUnapplyFrame and record.autoUnapplyFrame <= self._simulation.frame then
          -- Remove the event
          table.remove(self._eventHistory, i)
          if not frameToRegenerateFrom or record.event.frame < frameToRegenerateFrom then
            frameToRegenerateFrom = record.event.frame
          end
        end
      end
      -- Regenerate state history from the event furthest in the past
      if frameToRegenerateFrom then
        self:_regenerateStateHistoryOnOrAfterFrame(frameToRegenerateFrom)
      end
    end
  }
end

return GameRunner
