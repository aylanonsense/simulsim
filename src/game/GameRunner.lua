local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'

local GameRunner = {}

function GameRunner:new(params)
  params = params or {}
  local game = params.game
  local framesOfHistory = params.framesOfHistory or 30
  local allowTimeManipulation = params.allowTimeManipulation ~= false
  local framesBetweenStateSnapshots = params.framesBetweenStateSnapshots or 21
  local snapshotGenerationOffset = params.snapshotGenerationOffset or 0
  local isRenderable = params.isRenderable ~= false

  local runner = {
    -- Private vars
    _futureStates = {},
    _stateHistory = {},
    _eventHistory = {},
    _transformHistory = {},
    _allowTimeManipulation = allowTimeManipulation,
    _framesBetweenStateSnapshots = framesBetweenStateSnapshots,
    _snapshotGenerationOffset = snapshotGenerationOffset,
    _isRenderable = isRenderable,
    _frameToSettleFrom = nil,

    -- Public vars
    game = game,
    framesOfHistory = framesOfHistory,

    -- Public methods
    -- Adds an event to be applied on the given frame, which may trigger a rewind
    settleRecentChanges = function(self)
      local currFrame = self.game.frame
      local frameToSettleFrom = self._frameToSettleFrom
      self._frameToSettleFrom = nil
      if frameToSettleFrom and frameToSettleFrom <= self.game.frame then
        if self:_rewindToFrame(frameToSettleFrom - 1) then
          self:_invalidateStateHistoryOnOrAfterFrame(frameToSettleFrom)
          self:_generateStateSnapshot()
          return self:_fastForwardToFrame(currFrame, true)
        else
          return false
        end
      end
      return true
    end,
    applyEvent = function(self, event, params)
      if self.debugProperty then
        print('Running is applying ' .. event.type .. ' event at frame ' .. event.frame .. ' and it is now ' .. self.game.frame)
      end
      params = params or {}
      local preserveFrame = params.preserveFrame
      local preservedFrameAdjustment = params.preservedFrameAdjustment or 0
      local framesUntilAutoUnapply = params.framesUntilAutoUnapply
      -- If the event occurred too far in the past, there's not much we can do about it
      local maxAllowedAge = self.framesOfHistory
      if framesUntilAutoUnapply and framesUntilAutoUnapply < maxAllowedAge then
        maxAllowedAge = framesUntilAutoUnapply
      end
      if event.frame < self.game.frame - maxAllowedAge then
        if self.debugProperty then
          print(' DENIED - maxAgeAllowed')
        end
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
            if not self._allowTimeManipulation and frameToRegenerateFrom <= self.game.frame then
              if self.debugProperty then
                print(' DENIED - time manip')
              end
              return false
            else
              if self._eventHistory[i].preserveFrame then
                record.event = tableUtils.cloneTable(record.event)
                record.event.frame = self._eventHistory[i].event.frame + preservedFrameAdjustment
              end
              self._eventHistory[i] = record
              replacedEvent = true
            end
            break
          end
        end
        -- And regenerate states that are now invalid
        if frameToRegenerateFrom <= self.game.frame then
          if self._allowTimeManipulation then
            if not replacedEvent then
              table.insert(self._eventHistory, record)
            end
            if self._frameToSettleFrom then
              self._frameToSettleFrom = math.min(frameToRegenerateFrom, self._frameToSettleFrom)
            else
              self._frameToSettleFrom = frameToRegenerateFrom
            end
            if self.debugProperty then
              print(' WORKED - yay')
            end
            return true
          else
            if self.debugProperty then
              print(' DENIED - newp')
            end
            return false
          end
        else
          if not replacedEvent then
            table.insert(self._eventHistory, record)
          end
          if self.debugProperty then
            print(' WORKED - replaced')
          end
          return true
        end
      end
      if self.debugProperty then
        print(' DENIED - nothin')
      end
    end,
    -- Cancels an event that was applied prior
    unapplyEvent = function(self, eventId)
      -- Search for the event
      for i = #self._eventHistory, 1, -1 do
        local event = self._eventHistory[i].event
        if event.id == eventId then
          if not self._allowTimeManipulation and event.frame <= self.game.frame then
            return false
          else
            -- Remove the event
            table.remove(self._eventHistory, i)
            -- Regenerate state history if the event was applied in the past
            if event.frame <= self.game.frame then
              if self._frameToSettleFrom then
                self._frameToSettleFrom = math.min(event.frame, self._frameToSettleFrom)
              else
                self._frameToSettleFrom = event.frame
              end
            end
            return true
          end
        end
      end
      return false
    end,
    -- Sets the current state of the game, removing all past history in the process
    setState = function(self, state)
      if self._allowTimeManipulation then
        -- Only future history is still valid
        for i = #self._eventHistory, 1, -1 do
          if self._eventHistory[i].event.frame <= state.frame then
            table.remove(self._eventHistory, i)
          end
        end
        for i = #self._transformHistory, 1, -1 do
          if self._transformHistory[i].frame <= state.frame then
            table.remove(self._transformHistory, i)
          end
        end
        -- The only valid state is the current one
        self._frameToSettleFrom = nil
        tableUtils.clearProps(self._stateHistory)
        self:_generateStateSnapshot(tableUtils.cloneTable(state))
      end
      -- Set the game's state
      self.game:setState(state)
    end,
    -- Sets the state, or applies it to the past if the state is in the past, or schedules it to be applied in the future
    applyState = function(self, state)
      -- If the state represents a moment in the past, rewind to apply it
      if state.frame <= self.game.frame then
        if self._allowTimeManipulation then
          if self._frameToSettleFrom then
            self._frameToSettleFrom = math.min(state.frame, self._frameToSettleFrom)
          else
            self._frameToSettleFrom = state.frame
          end
          table.insert(self._futureStates, state)
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
      if not self._allowTimeManipulation and frame <= self.game.frame then
        return false
      else
        table.insert(self._transformHistory, { frame = frame, transform = transformFunc })
        -- If this is a moment in the past, take note that we'll need to apply it
        if frame <= self.game.frame then
          if self._frameToSettleFrom then
            self._frameToSettleFrom = math.min(frame, self._frameToSettleFrom)
          else
            self._frameToSettleFrom = frame
          end
        end
        return true
      end
    end,
    moveForwardOneFrame = function(self, dt)
      self:settleRecentChanges()
      self:_moveGameForwardOneFrame(dt, true, true)
      self:_removeOldHistory() -- TODO consider only doing this every so often
      if self._allowTimeManipulation then
        self:_autoUnapplyEvents()
      end
    end,
    reset = function(self)
      self.game:reset()
      tableUtils.clearProps(self._futureStates)
      tableUtils.clearProps(self._stateHistory)
      tableUtils.clearProps(self._eventHistory)
      tableUtils.clearProps(self._transformHistory)
      -- Re-trigger the game's load function
      self.game:load()
    end,
    rewind = function(self, numFrames)
      if self._allowTimeManipulation and self:_rewindToFrame(self.game.frame - numFrames) then
        self:_invalidateStateHistoryOnOrAfterFrame(self.game.frame + 1)
        return true
      else
        return false
      end
    end,
    fastForward = function(self, numFrames)
      return self._allowTimeManipulation and self:_fastForwardToFrame(self.game.frame + numFrames, true)
    end,

    -- Private methods
    -- Set the game to the state it was in after the given frame
    _rewindToFrame = function(self, frame)
      if self._allowTimeManipulation then
        -- Get a state from before or on the given frame
        local mostRecentState = nil
        for _, state in ipairs(self._stateHistory) do
          if state.frame <= frame and (mostRecentState == nil or mostRecentState.frame < state.frame) then
            mostRecentState = state
          end
        end
        if mostRecentState then
          -- Set the game to that state
          self.game:setState(tableUtils.cloneTable(mostRecentState))
          -- And then fast forward to the correct frame
          return self:_fastForwardToFrame(frame, false)
        end
      end
      return false
    end,
    -- Fast forwards the game to the given frame
    _fastForwardToFrame = function(self, frame, shouldGenerateStateSnapshots)
      if self._allowTimeManipulation then
        while self.game.frame < frame do
          self:_moveGameForwardOneFrame(1 / 60, false, shouldGenerateStateSnapshots)
        end
        return true
      else
        return false
      end
    end,
    -- Generates a state snapshot and adds it to the state history
    _generateStateSnapshot = function(self, state)
      if not state then
        state = tableUtils.cloneTable(self.game:getState())
      end
      table.insert(self._stateHistory, state)
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
      local currFrame = self.game.frame
      -- Rewind to just before that frame
      if self:_rewindToFrame(frame - 1) then
        -- All the state snapshots on or after the given frame are invalid now
        self:_invalidateStateHistoryOnOrAfterFrame(frame)
        -- And then play back to the frame we were just at, generating state history as we go
        return self:_fastForwardToFrame(currFrame, true)
      else
        return false
      end
    end,
    -- Advances the game forward one frame
    _moveGameForwardOneFrame = function(self, dt, isTopFrame, shouldGenerateStateSnapshots)
      -- Advance the game's time
      self.game.frame = self.game.frame + 1
      -- Get the events that take place on this frame
      local events = self:_getEventsAtFrame(self.game.frame)
      if self.debugProperty then
        for _, record in ipairs(self._eventHistory) do
          print('Runner has ' .. record.event.type .. ' event at frame ' .. record.event.frame .. ' and it is now ' .. self.game.frame)
        end
      end
      -- Input-related events are automatically applied to the game's inputs
      for _, event in ipairs(events) do
        if event.isInputEvent and event.type == 'set-inputs' then
          self.game.inputs[event.data.clientId] = event.data.inputs
          self.game.frameOfLastInput[event.data.clientId] = event.frame
        else
          self.game:resetEntityIdGeneration('event-' .. event.id .. '-')
          self.game:handleEvent(event.type, event.data, isTopFrame and self._isRenderable)
        end
      end
      -- Update the game
      self.game:resetEntityIdGeneration('frame-' .. self.game.frame .. '-')
      self.game:updateEntityMetadata(dt)
      self.game:update(dt, isTopFrame and self._isRenderable)
      -- Check to see if any scheduled states need to applied now
      for i = #self._futureStates, 1, -1 do
        if self._futureStates[i].frame == self.game.frame then
          self:setState(self._futureStates[i])
        end
        if self._futureStates[i].frame <= self.game.frame then
          table.remove(self._futureStates, i)
        end
      end
      -- Check to see if any scheduled transformations need to applied now
      for i = #self._transformHistory, 1, -1 do
        if self._transformHistory[i].frame == self.game.frame then
          self._transformHistory[i].transform(self.game)
        end
      end
      -- Generate a snapshot of the state every so often
      if shouldGenerateStateSnapshots and self._allowTimeManipulation and (self.game.frame + self._snapshotGenerationOffset) % self._framesBetweenStateSnapshots == 0 then
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
        if self._stateHistory[i].frame < self.game.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._stateHistory, i)
        end
      end
      -- Remove old event history
      for i = #self._eventHistory, 1, -1 do
        if self._eventHistory[i].event.frame < self.game.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._eventHistory, i)
        end
      end
      -- Remove old transformation history
      for i = #self._transformHistory, 1, -1 do
        if self._transformHistory[i].frame < self.game.frame - self.framesOfHistory - self._framesBetweenStateSnapshots then
          table.remove(self._transformHistory, i)
        end
      end
    end,
    -- Remove any events that should be automatically unapplied
    _autoUnapplyEvents = function(self)
      -- Find any events that need to be automatically unapplied
      local frameToRegenerateFrom = nil
      for i = #self._eventHistory, 1, -1 do
        local record = self._eventHistory[i]
        if record.autoUnapplyFrame and record.autoUnapplyFrame <= self.game.frame then
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

  -- Load the game
  game:load()

  return runner
end

return GameRunner
