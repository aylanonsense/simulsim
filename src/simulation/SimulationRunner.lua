local SimulationRunner = {}
function SimulationRunner:new(params)
  local simulation = params and params.simulation
  local framesOfHistory = params and params.framesOfHistory or 30
  local framesBetweenStateSnapshots = params and params.framesBetweenStateSnapshots or 5

  return {
    -- Private config vars
    _framesOfHistory = framesOfHistory,
    _framesBetweenStateSnapshots = framesBetweenStateSnapshots,

    -- Private vars
    _simulation = simulation,
    _stateHistory = {},
    _eventHistory = {},

    -- Public methods
    getSimulation = function(self)
      return self._simulation
    end,
    -- Adds an event to be applied on the given frame, which may trigger a rewind
    applyEvent = function(self, event)
      local currFrame = self._simulation.frame
      table.insert(self._eventHistory, event)
      -- If the event occurred too far in the past, there's not much we can do about it
      if event.frame < currFrame - self._framesOfHistory then
        return false
      -- If the event takes place in the past, regenerate the state history
      elseif event.frame <= currFrame then
        if not self:_regenerateStateHistoryOnOrAfterFrame(event.frame) then
          return false
        end
      end
      return true
    end,
    -- Sets the current state of the simulation, removing all past hitory in the process
    setState = function(self, state)
      -- Set the simulation's state
      self._simulation:setState(state)
      -- Only future events are still valid
      for i = #self._eventHistory, 1, -1 do
        if self._eventHistory[i].frame <= self._simulation.frame then
          table.remove(self._eventHistory, i)
        end
      end
      -- The only valid state is the current one
      self._stateHistory = {}
      self:_generateStateSnapshot()
    end,
    update = function(self, dt)
      -- TODO take dt into account
      self:_moveSimulationForwardOneFrame(true, true)
      self:_removeOldHistory()
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
        self:_moveSimulationForwardOneFrame(false, shouldGenerateStateSnapshots)
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
    _moveSimulationForwardOneFrame = function(self, isTopFrame, shouldGenerateStateSnapshots)
      local dt = 1 / 60
      -- Advance the simulation's time
      self._simulation.frame = self._simulation.frame + 1
      self._simulation.time = self._simulation.time + dt
      -- Look up the inputs and events that take place on this frame
      local inputs = {}
      local events = self:_getEventsAtFrame(self._simulation.frame)
      -- Update the simulation
      self._simulation:update(dt, {}, events, isTopFrame)
      -- Generate a snapshot of the state every so often
      if shouldGenerateStateSnapshots and self._simulation.frame % self._framesBetweenStateSnapshots == 0 then
        self:_generateStateSnapshot()
      end
    end,
    -- Get all events that occurred at the given frame
    _getEventsAtFrame = function(self, frame)
      local events = {}
      for _, event in ipairs(self._eventHistory) do
        if event.frame == frame then
          table.insert(events, event)
        end
      end
      return events
    end,
    -- Removes any state snapshots and events that are beyond the history threshold
    _removeOldHistory = function(self)
      -- Remove old state history
      for i = #self._stateHistory, 1, -1 do
        if self._stateHistory[i].frame < self._simulation.frame - self._framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._stateHistory, i)
        end
      end
      -- Remove old event history
      for i = #self._eventHistory, 1, -1 do
        if self._eventHistory[i].frame < self._simulation.frame - self._framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._eventHistory, i)
        end
      end
    end
  }
end

return SimulationRunner
