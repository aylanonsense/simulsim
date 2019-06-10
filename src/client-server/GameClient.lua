-- Load dependencies
local MessageClient = require 'src/client-server/MessageClient'
local GameRunner = require 'src/game/GameRunner'
local OffsetOptimizer = require 'src/transport/OffsetOptimizer'
local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'
local logger = require 'src/utils/logger'

local GameClient = {}

function GameClient:new(params)
  params = params or {}
  local conn = params.conn
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenPings = params.framesBetweenPings or 15
  local maxFramesOfLatency = params.maxFramesOfLatency or 180
  local exposeGameWithoutPrediction = params.exposeGameWithoutPrediction == true

  -- Create a game for the client and a runner for it
  local runner = GameRunner:new({
    game = gameDefinition:new(),
    isRenderable = true,
    allowTimeManipulation = false
  })
  local runnerWithoutSmoothing = GameRunner:new({
    game = gameDefinition:new(),
    isRenderable = false
  })
  local runnerWithoutPrediction
  local gameWithoutPrediction
  if exposeGameWithoutPrediction then
    runnerWithoutPrediction = GameRunner:new({
      game = gameDefinition:new(),
      isRenderable = false
    })
    gameWithoutPrediction = runnerWithoutPrediction.game
  end

  -- Create offset optimizers to minimize time desync and latency
  local timeSyncOptimizer = OffsetOptimizer:new({
    minOffsetBeforeImmediateCorrection = 0,
    maxOffsetBeforeImmediateCorrection = 20
  })
  local latencyOptimizer = OffsetOptimizer:new({
    minOffsetBeforeImmediateCorrection = 0,
    maxOffsetBeforeImmediateCorrection = 20
  })

  -- Wrap the raw connection in a message client to make it easier to work with
  local messageClient = MessageClient:new({ conn = conn })

  local client = {
    -- Private vars
    _runner = runner,
    _runnerWithoutSmoothing = runnerWithoutSmoothing,
    _runnerWithoutPrediction = runnerWithoutPrediction,
    _gameDefinition = gameDefinition,
    _clientFrame = 0,
    _hasSetInitialState = false,
    _hasStabilizedTimeOffset = false,
    _hasStabilizedLatency = false,
    _framesOfStableTimeOffset = 0,
    _framesOfStableLatency = 0,
    _messageClient = messageClient,
    _timeSyncOptimizer = timeSyncOptimizer,
    _latencyOptimizer = latencyOptimizer,
    _framesOfLatency = 0,
    _framesUntilNextPing = framesBetweenPings,
    _framesUntilNextFlush = framesBetweenFlushes,
    _framesBetweenPings = framesBetweenPings,
    _framesBetweenFlushes = framesBetweenFlushes,
    _maxFramesOfLatency = maxFramesOfLatency,
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _stabilizeCallbacks = {},
    _destabilizeCallbacks = {},

    -- Public vars
    clientId = nil,
    data = {},
    game = runner.game,
    gameWithoutSmoothing = runnerWithoutSmoothing.game,
    gameWithoutPrediction = gameWithoutPrediction,

    -- Public methods
    connect = function(self, handshake)
      logger.info('Client connecting to server')
      self._messageClient:connect(handshake)
    end,
    disconnect = function(self, reason)
      self._messageClient:disconnect(reason)
    end,
    isConnecting = function(self)
      return self._messageClient:isConnecting()
    end,
    isConnected = function(self)
      return self._messageClient:isConnected()
    end,
    isStable = function(self)
      return self._hasSetInitialState and self._hasStabilizedTimeOffset and self._hasStabilizedLatency
    end,
    getFramesOfLatency = function(self)
      return self._framesOfLatency
    end,
    fireEvent = function(self, eventType, eventData, params)
      params = params or {}
      local isInputEvent = params.isInputEvent
      local predictClientSide = params.predictClientSide ~= false
      local maxFramesLate = params.maxFramesLate or 0
      local maxFramesEarly = params.maxFramesEarly or 20
      local applyImmediatelyWhenEarly = params.applyImmediatelyWhenEarly == true
      if self._messageClient:isConnected() then
        -- Create a new event
        local event = self:_addClientMetadata({
          id = 'client-' .. self.clientId .. '-' .. stringUtils.generateRandomString(10),
          frame = self.gameWithoutSmoothing.frame + self._framesOfLatency + 1,
          type = eventType,
          data = eventData,
          isInputEvent = isInputEvent
        })
        event.clientMetadata.maxFramesLate = maxFramesLate
        event.clientMetadata.maxFramesEarly = maxFramesEarly
        event.clientMetadata.applyImmediatelyWhenEarly = applyImmediatelyWhenEarly
        -- Apply a prediction of the event
        if predictClientSide then
          local serverEvent = tableUtils.cloneTable(event)
          if self._runnerWithoutPrediction then
            self._runnerWithoutPrediction:applyEvent(serverEvent, {
              framesUntilAutoUnapply = self._framesOfLatency + 5
            })
          end
          local clientEvent = tableUtils.cloneTable(event)
          clientEvent.frame = self.gameWithoutSmoothing.frame + 1
          self._runnerWithoutSmoothing:applyEvent(clientEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5,
            preserveFrame = true
          })
          self._runner:applyEvent(clientEvent, {
            preserveFrame = true
          })
        end
        -- Send the event to the server
        self._messageClient:buffer({ 'event', event })
        -- Send immediately if we're not buffering
        if self._framesBetweenFlushes <= 0 then
          self._messageClient:flush()
        end
        -- Return the event
        return event
      end
    end,
    setInputs = function(self, inputs, params)
      params = params or {}
      params.isInputEvent = true
      params.maxFramesLate = params.maxFramesLate or 3
      params.maxFramesEarly = params.maxFramesEarly or 30
      return self:fireEvent('set-inputs', {
        clientId = self.clientId,
        inputs = inputs
      }, params)
    end,
    update = function(self, dt)
      -- Update the underlying messaging client
      self._messageClient:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      self._clientFrame = self._clientFrame + 1
      -- Update the game (via the game runner)
      self._runner:moveForwardOneFrame(dt)
      self._runnerWithoutSmoothing:moveForwardOneFrame(dt)
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:moveForwardOneFrame(dt)
      end
      if self._messageClient:isConnected() then
        local wasStable = self._hasSetInitialState and self._hasStabilizedTimeOffset and self._hasStabilizedLatency
        -- Update the timing and latency optimizers
        self._timeSyncOptimizer:moveForwardOneFrame(dt)
        self._latencyOptimizer:moveForwardOneFrame(dt)
        -- Check to see if we've stabilized
        if self._hasSetInitialState then
          self._framesOfStableTimeOffset = self._framesOfStableTimeOffset + 1
          if self._framesOfStableTimeOffset > 60 then
            self._hasStabilizedTimeOffset = true
          end
          if self._hasStabilizedTimeOffset then
            self._framesOfStableLatency = self._framesOfStableLatency + 1
            if self._framesOfStableLatency > 60 then
              self._hasStabilizedLatency = true
            end
          end
        end
        -- Rewind or fast forward the game to get it synced with the server
        local timeAdjustment = self._timeSyncOptimizer:getRecommendedAdjustment()
        if timeAdjustment and self._hasSetInitialState then
          self._timeSyncOptimizer:reset()
          -- If the time offset optimizer is recommending a huge adjustment, that means we've desynced
          if timeAdjustment > 90 or timeAdjustment < -90 then
            logger.info('Client ' .. self.clientId .. ' destabilized due to time becoming too desynced [frame=' .. self.game.frame .. ']')
            self:_handleDestabilize()
          -- Otherwise, adjust the time offset
          elseif timeAdjustment ~= 0 then
            self._framesOfStableTimeOffset = 0
            if timeAdjustment > 2 or timeAdjustment < -2 then
              self._hasStabilizedTimeOffset = false
              self._hasStabilizedLatency = false
              self._framesOfStableLatency = 0
            end
            -- Fast forward if we're behind the states the server is sending us
            if timeAdjustment > 0 then
              logger.debug('Client ' .. self.clientId .. ' fast forwarding ' .. timeAdjustment .. ' frames to sync time with server [frame=' .. self.game.frame .. ']')
              local fastForwardSuccessful = self._runnerWithoutSmoothing:fastForward(timeAdjustment)
              if self._runnerWithoutPrediction then
                fastForwardSuccessful = fastForwardSuccessful and self._runnerWithoutPrediction:fastForward(timeAdjustment)
              end
              if not fastForwardSuccessful then
                logger.info('Client ' .. self.clientId .. ' destabilized due to failed fast forward [frame=' .. self.game.frame .. ']')
                self:_handleDestabilize()
              end
            -- Rewind if we're ahead of the states the server is sending us
            elseif timeAdjustment < 0 then
              logger.debug('Client ' .. self.clientId .. ' rewinding ' .. timeAdjustment .. ' frames to sync time with server [frame=' .. self.game.frame .. ']')
              local rewindSuccessful = self._runnerWithoutSmoothing:rewind(-timeAdjustment)
              if self._runnerWithoutPrediction then
                rewindSuccessful = rewindSuccessful and self._runnerWithoutPrediction:rewind(-timeAdjustment)
              end
              if not rewindSuccessful then
                logger.info('Client ' .. self.clientId .. ' destabilized due to failed rewind [frame=' .. self.game.frame .. ']')
                self:_handleDestabilize()
              end
            end
          end
        end
        -- Adjust latency to ensure messages are arriving on time server-side
        local latencyAdjustment = self._latencyOptimizer:getRecommendedAdjustment()
        if latencyAdjustment and self._hasSetInitialState and self._hasStabilizedTimeOffset then
          self._latencyOptimizer:reset()
          -- If the latency optimizer is recommending a huge adjustment, that means we've destabilized
          if latencyAdjustment > 90 or latencyAdjustment < -90 then
            self._framesOfLatency = 20
            logger.info('Client ' .. self.clientId .. ' destabilized due to latency becoming too desynced [frame=' .. self.game.frame .. ']')
            self:_handleDestabilize()
          -- Otherwise, adjust the latency
          elseif latencyAdjustment ~= 0 then
            self._framesOfStableLatency = 0
            if latencyAdjustment > 2 or latencyAdjustment < -2 then
              self._hasStabilizedLatency = false
            end
            if latencyAdjustment < 0 then
              latencyAdjustment = math.floor(1.15 * latencyAdjustment)
            end
            local prevFramesOfLatency = self._framesOfLatency
            self._framesOfLatency = math.min(math.max(0, self._framesOfLatency - latencyAdjustment), self._maxFramesOfLatency)
            local change = self._framesOfLatency - prevFramesOfLatency
            logger.info('Client ' .. self.clientId .. ' adjusting latency from ' .. prevFramesOfLatency .. ' to ' .. self._framesOfLatency .. ' frames (' .. (change >= 0 and '+' .. change or change) .. ') [frame=' .. self.game.frame .. ']')
          end
        end
        -- Check for stabilizing or destabilizing
        local isStable = self._hasSetInitialState and self._hasStabilizedTimeOffset and self._hasStabilizedLatency
        if wasStable and not isStable then
          self._framesUntilNextPing = 0
          for _, callback in ipairs(self._destabilizeCallbacks) do
            callback()
          end
        elseif isStable and not wasStable then
          logger.info('Client ' .. self.clientId .. ' stabilized connection to server [frame=' .. self.game.frame .. ']')
          for _, callback in ipairs(self._stabilizeCallbacks) do
            callback()
          end
        end
        -- Send a lazy ping every so often to gauge latency accuracy
        self._framesUntilNextPing = self._framesUntilNextPing - 1
        if self._framesUntilNextPing <= 0 then
          self._framesUntilNextPing = isStable and self._framesBetweenPings or 2
          self:_ping()
        end
      end
      -- Flush the client's messages every so often
      self._framesUntilNextFlush = self._framesUntilNextFlush - 1
      if self._framesUntilNextFlush <= 0 then
        self._framesUntilNextFlush = self._framesBetweenFlushes
        self._messageClient:flush()
      end
      -- Make sure we have enough recorded history to be operational
      if self._runnerWithoutSmoothing.framesOfHistory > math.max(self._framesOfLatency + 10, 30) then
        self._runnerWithoutSmoothing.framesOfHistory = self._runnerWithoutSmoothing.framesOfHistory - 1
      else
        self._runnerWithoutSmoothing.framesOfHistory = math.min(self._framesOfLatency + 10, 300)
      end
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction.framesOfHistory = self._runnerWithoutSmoothing.framesOfHistory
      end
      -- Smooth game
      self:_smoothGame()
    end,
    simulateNetworkConditions = function(self, params)
      self._messageClient:simulateNetworkConditions(params)
    end,

    -- Overrideable methods
    syncEntity = function(self, game, entity, candidateEntity, isPrediction)
      local isEntityUsingPrediction
      if entity then
        isEntityUsingPrediction = self:isEntityUsingPrediction(entity, self.clientId)
      else
        isEntityUsingPrediction = self:isEntityUsingPrediction(candidateEntity, self.clientId)
      end
      if isEntityUsingPrediction == isPrediction then
        return candidateEntity
      else
        return entity
      end
    end,
    syncInputs = function(self, game, inputs, candidateInputs, isPrediction)
      if isPrediction then
        inputs[self.clientId] = candidateInputs[self.clientId]
        return inputs
      else
        candidateInputs[self.clientId] = inputs[self.clientId]
        return candidateInputs
      end
    end,
    syncData = function(self, game, data, candidateData, isPrediction)
      if isPrediction then
        return data
      else
        return candidateData
      end
    end,
    smoothEntity = function(self, game, entity, idealEntity)
      return idealEntity
    end,
    smoothInputs = function(self, game, inputs, idealInputs)
      return idealInputs
    end,
    smoothData = function(self, game, data, idealData)
      return idealData
    end,
    isEntityUsingPrediction = function(self, entity)
      return entity and entity.clientId == self.clientId
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onConnectFailure = function(self, callback)
      table.insert(self._connectFailureCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onStabilize = function(self, callback)
      table.insert(self._stabilizeCallbacks, callback)
    end,
    onDestabilize = function(self, callback)
      table.insert(self._destabilizeCallbacks, callback)
    end,

    -- Private methods
    _handleConnect = function(self, connectionData)
      self.clientId = connectionData[1]
      logger.info('Client ' .. self.clientId .. ' connected to server [frame=' .. connectionData[3].frame .. ']')
      self.data = connectionData[2]
      self._framesOfLatency = 20
      self:_setInitialState(connectionData[3])
      -- Trigger connect callbacks
      for _, callback in ipairs(self._connectCallbacks) do
        callback()
      end
    end,
    _setInitialState = function(self, state)
      self._hasSetInitialState = true
      self._framesUntilNextPing = 0
      self._framesUntilNextFlush = 0
      self._timeSyncOptimizer:reset()
      self._latencyOptimizer:reset()
      -- Set the state of the client-side game
      self._runnerWithoutSmoothing:reset()
      self._runnerWithoutSmoothing:setState(state)
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:reset()
        self._runnerWithoutPrediction:setState(state)
      end
    end,
    _handleDestabilize = function(self)
      self._hasSetInitialState = false
      self._hasStabilizedTimeOffset = false
      self._hasStabilizedLatency = false
      self._framesOfStableTimeOffset = 0
      self._framesOfStableLatency = 0
      self._timeSyncOptimizer:reset()
      self._latencyOptimizer:reset()
    end,
    _handleConnectFailure = function(self, reason)
      logger.info('Client failed to connect to server: ' .. (reason or 'No reason given'))
      -- Trigger connect failure callbacks
      for _, callback in ipairs(self._connectFailureCallbacks) do
        callback(reason or 'Failed to connect to server')
      end
    end,
    _handleDisconnect = function(self, reason)
      logger.info('Client ' .. self.clientId .. ' disconnected from server: ' .. (reason or 'No reason given') .. '[frame=' .. self.game.frame .. ']')
      self._framesOfLatency = 0
      self._hasSetInitialState = false
      self._hasStabilizedLatency = false
      -- Trigger dicconnect callbacks
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(reason or 'Connection terminated')
      end
    end,
    _handleReceive = function(self, messageType, messageContent)
      if messageType == 'event' then
        self:_handleReceiveEvent(messageContent)
      elseif messageType == 'reject-event' then
        self:_handleRejectEvent(messageContent)
      elseif messageType == 'ping-response' then
        self:_handlePingResponse(messageContent)
      elseif messageType == 'state-snapshot' then
        self:_handleStateSnapshot(messageContent)
      end
    end,
    _handleReceiveEvent = function(self, event)
      if event.serverMetadata and event.serverMetadata.frame then
        self:_recordTimeOffset(event.serverMetadata.frame)
      end
      local preservedFrameAdjustment = 0
      if event.serverMetadata and event.serverMetadata.proposedEventFrame then
        preservedFrameAdjustment = event.frame - event.serverMetadata.proposedEventFrame
      end
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata)
      self:_applyEvent(event, { preservedFrameAdjustment = preservedFrameAdjustment })
    end,
    _handleRejectEvent = function(self, event)
      logger.silly('Client ' .. self.clientId .. ' informed that "' .. event.type .. '" event on frame ' .. event.frame .. ' was rejected by server [frame=' .. self.game.frame .. ']')
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata)
      self:_unapplyEvent(event)
    end,
    _handlePingResponse = function(self, ping)
      self:_recordTimeOffset(ping.frame)
      self:_recordLatencyOffset(ping.clientMetadata, ping.serverMetadata)
    end,
    _syncToTargetGame = function(self, sourceGame, targetGame, isPrediction)
      -- Sync entities that exist in the target game
      local entityExistsInTargetGame = {}
      for _, targetEntity in ipairs(targetGame.entities) do
        local id = targetGame:getEntityId(targetEntity)
        entityExistsInTargetGame[id] = true
        local sourceEntity, index = sourceGame:getEntityById(id)
        local isSyncEnabled
        if sourceEntity then
          isSyncEnabled = sourceGame:isSyncEnabledForEntity(sourceEntity) and targetGame:isSyncEnabledForEntity(targetEntity)
        else
          isSyncEnabled = targetGame:isSyncEnabledForEntity(targetEntity)
        end
        if isSyncEnabled then
          local syncedEntity = self:syncEntity(sourceGame, sourceEntity, targetEntity, isPrediction)
          -- Entity was removed
          if not syncedEntity and sourceEntity then
            table.remove(sourceGame.entities, index)
          -- Entity was added
          elseif syncedEntity and not sourceEntity then
            table.insert(sourceGame.entities, syncedEntity)
          -- Entity was modified or swapped out
          elseif syncedEntity and sourceEntity then
            sourceGame.entities[index] = syncedEntity
          end
        end
      end
      -- Sync entities that don't exist in the target game
      for index = #sourceGame.entities, 1, -1 do
        local sourceEntity = sourceGame.entities[index]
        local id = sourceGame:getEntityId(sourceEntity)
        if not entityExistsInTargetGame[id] and sourceGame:isSyncEnabledForEntity(sourceEntity) then
          local syncedEntity = self:syncEntity(sourceGame, sourceEntity, nil, isPrediction)
          -- Entity was removed
          if not syncedEntity then
            table.remove(sourceGame.entities, index)
          -- Entity was modified or swapped out
          else
            sourceGame.entities[index] = syncedEntity
          end
        end
      end
      -- Sync data
      sourceGame.data = self:syncData(sourceGame, sourceGame.data, tableUtils.cloneTable(targetGame.data), isPrediction)
      -- Sync inputs
      sourceGame.inputs = self:syncInputs(sourceGame, sourceGame.inputs, tableUtils.cloneTable(targetGame.inputs), isPrediction)
    end,
    _handleStateSnapshot = function(self, state)
      if not self._hasSetInitialState then
        self:_setInitialState(state)
      else
        self:_recordTimeOffset(state.frame)
        -- state represents what the game would currently look like with no client-side prediction
        if self._runnerWithoutPrediction then
          self._runnerWithoutPrediction:applyState(state)
        end
        -- Fix client-predicted inconsistencies in the past
        self._runnerWithoutSmoothing:applyStateTransform(state.frame - self._framesOfLatency, function(game)
          self:_syncToTargetGame(self.gameWithoutSmoothing, self._gameDefinition:new({ initialState = state }), true)
        end)
        -- Fix non-predicted inconsistencies in the present
        self._runnerWithoutSmoothing:applyStateTransform(state.frame, function(game)
          self:_syncToTargetGame(self.gameWithoutSmoothing, self._gameDefinition:new({ initialState = state }), false)
        end)
      end
    end,
    _smoothGame = function(self)
      local isStable = self._hasSetInitialState and self._hasStabilizedTimeOffset and self._hasStabilizedLatency
      local sourceGame = self.game
      local targetGame = self.gameWithoutSmoothing:clone()
      -- Just copy the current frame
      sourceGame.frame = targetGame.frame
      -- Smooth entities
      local entityExistsInTargetGame = {}
      for _, targetEntity in ipairs(targetGame.entities) do
        local id = targetGame:getEntityId(targetEntity)
        entityExistsInTargetGame[id] = true
        local sourceEntity, index = sourceGame:getEntityById(id)
        local smoothedEntity
        if isStable or not sourceEntity then
          smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, targetEntity)
        else
          smoothedEntity = sourceEntity
        end
        -- Entity was removed
        if not smoothedEntity and sourceEntity then
          table.remove(sourceGame.entities, index)
        -- Entity was added
        elseif smoothedEntity and not sourceEntity then
          table.insert(sourceGame.entities, smoothedEntity)
        -- Entity was modified or swapped out
        elseif smoothedEntity and sourceEntity then
          sourceGame.entities[index] = smoothedEntity
        end
      end
      -- Sync entities that don't exist in the target game
      for index = #sourceGame.entities, 1, -1 do
        local sourceEntity = sourceGame.entities[index]
        local id = sourceGame:getEntityId(sourceEntity)
        if not entityExistsInTargetGame[id] then
          local smoothedEntity
          if isStable then
            smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, nil)
          else
            smoothedEntity = sourceEntity
          end
          -- Entity was removed
          if not smoothedEntity then
            table.remove(sourceGame.entities, index)
          -- Entity was modified or swapped out
          else
            sourceGame.entities[index] = smoothedEntity
          end
        end
      end
      -- Smooth inputs
      sourceGame.inputs = self:smoothInputs(sourceGame, sourceGame.inputs, targetGame.inputs)
      -- Smooth data
      sourceGame.data = self:smoothData(sourceGame, sourceGame.data, targetGame.data)
    end,
    _applyEvent = function(self, event, params)
      if event.frame > self._runner.game.frame then
        self._runner:applyEvent(event, params)
      end
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:applyEvent(event, params)
      end
      return self._runnerWithoutSmoothing:applyEvent(event, params)
    end,
    _unapplyEvent = function(self, event)
      if event.frame > self._runner.game.frame then
        self._runner:unapplyEvent(event)
      end
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:unapplyEvent(event)
      end
      return self._runnerWithoutSmoothing:unapplyEvent(event)
    end,
    _ping = function(self)
      -- Send a ping to the server, no need to flush immediately since we want the buffer time to be accounted for
      self._messageClient:buffer({ 'ping', self:_addClientMetadata({}) })
      -- But flush immediately if we have no auto-flushing
      if self._framesBetweenFlushes <= 0 then
        self._messageClient:flush()
      end
    end,
    _addClientMetadata = function(self, obj)
      local frame = self.gameWithoutSmoothing.frame
      obj.clientMetadata = {
        clientId = self.clientId,
        clientFrameSent = self._clientFrame
      }
      return obj
    end,
    _recordTimeOffset = function(self, frame)
      if self._hasSetInitialState then
        self._timeSyncOptimizer:recordOffset(frame - self.gameWithoutSmoothing.frame - 1)
      end
    end,
    _recordLatencyOffset = function(self, clientMetadata, serverMetadata)
      if clientMetadata and clientMetadata.clientId == self.clientId and serverMetadata and serverMetadata.frame then
        -- Figure out when we'd expect the packet to arrive if it had been sent with current network conditions
        local timeOffsetNow = self.gameWithoutSmoothing.frame - self._clientFrame
        local latencyNow = self._framesOfLatency
        local expectedFrameReceived = clientMetadata.clientFrameSent + timeOffsetNow + latencyNow
        self._latencyOptimizer:recordOffset(expectedFrameReceived - serverMetadata.frame)
      end
    end
  }

  -- Bind events
  messageClient:onConnect(function(connectionData)
    client:_handleConnect(connectionData)
  end)
  messageClient:onConnectFailure(function(reason)
    client:_handleConnectFailure(reason)
  end)
  messageClient:onDisconnect(function(reason)
    client:_handleDisconnect(reason)
  end)
  messageClient:onReceive(function(msg)
    client:_handleReceive(msg[1], msg[2])
  end)

  return client
end

return GameClient
