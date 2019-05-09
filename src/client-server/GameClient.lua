-- Load dependencies
local MessageClient = require 'src/client-server/MessageClient'
local GameRunner = require 'src/game/GameRunner'
local OffsetOptimizer = require 'src/transport/OffsetOptimizer'
local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'

local GameClient = {}
function GameClient:new(params)
  params = params or {}
  local conn = params.conn
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenPings = params.framesBetweenPings or 15
  local maxFramesOfLatency = params.maxFramesOfLatency or 180

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
  local runnerWithoutPrediction = GameRunner:new({
    game = gameDefinition:new(),
    isRenderable = false
  })

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
    _hasSyncedTime = false,
    _hasSyncedLatency = false,
    _messageClient = messageClient,
    _timeSyncOptimizer = timeSyncOptimizer,
    _latencyOptimizer = latencyOptimizer,
    _syncId = nil,
    _framesOfLatency = 0,
    _framesUntilNextPing = framesBetweenPings,
    _framesUntilNextFlush = framesBetweenFlushes,
    _framesBetweenPings = framesBetweenPings,
    _framesBetweenFlushes = framesBetweenFlushes,
    _maxFramesOfLatency = maxFramesOfLatency,
    _connectCallbacks = {},
    _connectFailureCallbacks = {},
    _disconnectCallbacks = {},
    _syncCallbacks = {},
    _desyncCallbacks = {},

    -- Public vars
    clientId = nil,
    data = {},
    game = runner.game,
    gameWithoutSmoothing = runnerWithoutSmoothing.game,
    gameWithoutPrediction = runnerWithoutPrediction.game,

    -- Public methods
    connect = function(self, handshake)
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
    isSynced = function(self)
      return self._hasSyncedTime and self._hasSyncedLatency
    end,
    getFramesOfLatency = function(self)
      return self._framesOfLatency
    end,
    fireEvent = function(self, eventType, eventData, params)
      params = params or {}
      local isInputEvent = params.isInputEvent
      local predictClientSide = params.predictClientSide ~= false
      if self._messageClient:isConnected() then
        -- Create a new event
        local event = self:_addClientMetadata({
          id = 'client-' .. self.clientId .. '-' .. stringUtils.generateRandomString(10),
          frame = self.gameWithoutSmoothing.frame + self._framesOfLatency + 1,
          type = eventType,
          data = eventData,
          isInputEvent = isInputEvent
        })
        -- Apply a prediction of the event
        if predictClientSide then
          local serverEvent = tableUtils.cloneTable(event)
          self._runnerWithoutPrediction:applyEvent(serverEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5
          })
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
      if self._messageClient:isConnected() then
        self:fireEvent('set-inputs', {
          clientId = self.clientId,
          inputs = inputs
        }, params)
      end
    end,
    update = function(self, dt)
      -- Update the underlying messaging client
      self._messageClient:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      local wasSynced = self._hasSyncedTime and self._hasSyncedLatency
      -- Update the game (via the game runner)
      self._runner:moveForwardOneFrame(dt)
      self._runnerWithoutSmoothing:moveForwardOneFrame(dt)
      self._runnerWithoutPrediction:moveForwardOneFrame(dt)
      if self._messageClient:isConnected() then
        -- Update the timing and latency optimizers
        self._timeSyncOptimizer:moveForwardOneFrame(dt)
        self._latencyOptimizer:moveForwardOneFrame(dt)
        -- Rewind or fast forward the game to get it synced with the server
        local timeAdjustment = self._timeSyncOptimizer:getRecommendedAdjustment()
        if self._hasSyncedTime and timeAdjustment then
          if timeAdjustment > 90 or timeAdjustment < -90 then
            self:_handleDesync()
          elseif timeAdjustment ~= 0 then
            if timeAdjustment > 0 then
              local fastForward1Successful = self._runnerWithoutSmoothing:fastForward(timeAdjustment)
              local fastForward2Successful = self._runnerWithoutPrediction:fastForward(timeAdjustment)
              if not fastForward1Successful or not fastForward2Successful then
                self:_handleDesync()
              end
            elseif timeAdjustment < 0 then
              local rewind1Successful = self._runnerWithoutSmoothing:rewind(-timeAdjustment)
              local rewind2Successful = self._runnerWithoutPrediction:rewind(-timeAdjustment)
              if not rewind1Successful or not rewind2Successful then
                self:_handleDesync()
              end
            end
            if self._hasSyncedTime then
              self._timeSyncOptimizer:reset()
              if -5 < timeAdjustment and timeAdjustment < 5 then
                self._framesOfLatency = math.min(math.max(0, self._framesOfLatency - timeAdjustment), self._maxFramesOfLatency)
                self._latencyOptimizer:reset()
              end
              self._syncId = stringUtils.generateRandomString(6)
            end
          end
        end
        -- Adjust latency to ensure messages are arriving on time server-side
        local latencyAdjustment = self._latencyOptimizer:getRecommendedAdjustment()
        if self._hasSyncedTime and latencyAdjustment then
          if latencyAdjustment > 90 or latencyAdjustment < -90 then
            self:_handleDesync()
          else
            self._hasSyncedLatency = true
            if self._hasSyncedTime and latencyAdjustment ~= 0 then
              self._framesOfLatency = math.min(math.max(0, self._framesOfLatency - latencyAdjustment), self._maxFramesOfLatency)
              self._syncId = stringUtils.generateRandomString(6)
              self._latencyOptimizer:reset()
            end
            if not wasSynced then
              for _, callback in ipairs(self._syncCallbacks) do
                callback()
              end
            end
          end
        end
        -- Send a lazy ping every so often to gauge latency accuracy
        self._framesUntilNextPing = self._framesUntilNextPing - 1
        if self._framesUntilNextPing <= 0 then
          self._framesUntilNextPing = self._framesBetweenPings
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
      self._runnerWithoutPrediction.framesOfHistory = self._runnerWithoutSmoothing.framesOfHistory
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
    onSync = function(self, callback)
      table.insert(self._syncCallbacks, callback)
    end,
    onDesync = function(self, callback)
      table.insert(self._desyncCallbacks, callback)
    end,

    -- Private methods
    _handleConnect = function(self, connectionData)
      self.clientId = connectionData[1]
      self.data = connectionData[2]
      self._framesOfLatency = 45
      self:_syncWithState(connectionData[3])
      -- Trigger connect callbacks
      for _, callback in ipairs(self._connectCallbacks) do
        callback()
      end
    end,
    _syncWithState = function(self, state)
      self._hasSyncedTime = true
      self._hasSyncedLatency = false
      self._syncId = stringUtils.generateRandomString(6)
      self._framesUntilNextPing = 0
      self._framesUntilNextFlush = 0
      self._timeSyncOptimizer:reset()
      self._latencyOptimizer:reset()
      -- Set the state of the client-side game
      self._runnerWithoutSmoothing:reset()
      self._runnerWithoutSmoothing:setState(state)
      self._runnerWithoutPrediction:reset()
      self._runnerWithoutPrediction:setState(state)
    end,
    _handleDesync = function(self)
      local wasSynced = self._hasSyncedTime and self._hasSyncedLatency
      self._hasSyncedTime = false
      self._hasSyncedLatency = false
      if wasSynced then
        for _, callback in ipairs(self._desyncCallbacks) do
          callback()
        end
      end
    end,
    _handleConnectFailure = function(self, reason)
      -- Trigger connect failure callbacks
      for _, callback in ipairs(self._connectFailureCallbacks) do
        callback(reason or 'Failed to connect to server')
      end
    end,
    _handleDisconnect = function(self, reason)
      self._framesOfLatency = 0
      self._syncId = nil
      self._hasSyncedTime = false
      self._hasSyncedLatency = false
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
      self:_recordTimeSyncOffset(event.frame)
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata)
      self:_applyEvent(event)
    end,
    _handleRejectEvent = function(self, event)
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata)
      self:_unapplyEvent(event)
    end,
    _handlePingResponse = function(self, ping)
      self:_recordTimeSyncOffset(ping.frame)
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
      if not self._hasSyncedTime then
        self:_syncWithState(state)
      else
        self:_recordTimeSyncOffset(state.frame)
        -- state represents what the game would currently look like with no client-side prediction
        self._runnerWithoutPrediction:applyState(state)
        -- Fix client-predicted inconsistencies in the past
        self._runnerWithoutSmoothing:applyStateTransform(state.frame - self._framesOfLatency, function(game)
          self:_syncToTargetGame(self.gameWithoutSmoothing, gameDefinition:new({ initialState = state }), true)
        end)
        -- Fix non-predicted inconsistencies in the present
        self._runnerWithoutSmoothing:applyStateTransform(state.frame, function(game)
          self:_syncToTargetGame(self.gameWithoutSmoothing, gameDefinition:new({ initialState = state }), false)
        end)
      end
    end,
    _smoothGame = function(self)
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
        local smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, targetEntity)
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
          local smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, nil)
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
    _applyEvent = function(self, event)
      if event.frame > self._runner.game.frame then
        self._runner:applyEvent(event)
      end
      self._runnerWithoutPrediction:applyEvent(event)
      return self._runnerWithoutSmoothing:applyEvent(event)
    end,
    _unapplyEvent = function(self, event)
      if event.frame > self._runner.game.frame then
        self._runner:unapplyEvent(event)
      end
      self._runnerWithoutPrediction:unapplyEvent(event)
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
        frameSent = frame,
        expectedFrameReceived = frame + self._framesOfLatency,
        framesOfLatency = self._framesOfLatency,
        syncId = self._syncId
      }
      return obj
    end,
    _recordTimeSyncOffset = function(self, frame)
      if self._hasSyncedTime then
        self._timeSyncOptimizer:recordOffset(frame - self.gameWithoutSmoothing.frame - 1)
      end
    end,
    _recordLatencyOffset = function(self, clientMetadata, serverMetadata)
      if self._hasSyncedTime then
        if clientMetadata and clientMetadata.clientId == self.clientId and clientMetadata.syncId == self._syncId then
          if serverMetadata and serverMetadata.frameReceived then
            self._latencyOptimizer:recordOffset(clientMetadata.expectedFrameReceived - serverMetadata.frameReceived)
          end
        end
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
