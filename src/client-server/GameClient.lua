-- Load dependencies
local MessageClient = require 'src/client-server/MessageClient'
local constants = require 'src/client-server/gameConstants'
local GameRunner = require 'src/game/GameRunner'
local LatencyGuesstimator = require 'src/sync/LatencyGuesstimator'
local FrameOffsetGuesstimator = require 'src/sync/FrameOffsetGuesstimator'
local tableUtils = require 'src/utils/table'
local stringUtils = require 'src/utils/string'
local logger = require 'src/utils/logger'

local GameClient = {}

function GameClient:new(params)
  params = params or {}
  local conn = params.conn
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenPings = params.framesBetweenPings or 16
  local framesBetweenSmoothing = params.framesBetweenSmoothing or 5
  local maxFramesOfLatency = params.maxFramesOfLatency or 180
  local framesBetweenStateSnapshots = params.framesBetweenStateSnapshots or 21
  local exposeGameWithoutPrediction = params.exposeGameWithoutPrediction == true
  local cullRedundantEvents = params.cullRedundantEvents ~= false

  -- Create a game for the client and a runner for it
  local runner = GameRunner:new({
    game = gameDefinition:new(),
    isRenderable = true,
    allowTimeManipulation = false
  })
  local runnerWithoutSmoothing = GameRunner:new({
    game = gameDefinition:new(),
    isRenderable = false,
    framesBetweenStateSnapshots = framesBetweenStateSnapshots,
    snapshotGenerationOffset = 0
  })
  local runnerWithoutPrediction
  local gameWithoutPrediction
  if exposeGameWithoutPrediction then
    runnerWithoutPrediction = GameRunner:new({
      game = gameDefinition:new(),
      isRenderable = false,
      framesBetweenStateSnapshots = framesBetweenStateSnapshots,
      snapshotGenerationOffset = math.floor(framesBetweenStateSnapshots / 2)
    })
    gameWithoutPrediction = runnerWithoutPrediction.game
  end

  -- Create guesstimators to minimize time desync and latency
  local latencyGuesstimator = LatencyGuesstimator:new({
    lowerGuessWeight = 0.45,
    raiseGuessWeight = 0.10
  })
  local frameOffsetGuesstimator = FrameOffsetGuesstimator:new({
    lowerGuessWeight = 0.10,
    raiseGuessWeight = 0.10
  })

  -- Wrap the raw connection in a message client to make it easier to work with
  local messageClient = MessageClient:new({ conn = conn })

  local client = {
    -- Private vars
    _runner = runner,
    _runnerWithoutSmoothing = runnerWithoutSmoothing,
    _runnerWithoutPrediction = runnerWithoutPrediction,
    _gameDefinition = gameDefinition,
    _clientTime = 0.00,
    _clientFrame = 0,
    _hasSetInitialState = false,
    _hasInitializedFrameOffset = false,
    _hasInitializedLatency = false,
    _cullRedundantEvents = cullRedundantEvents,
    _messageClient = messageClient,
    _latencyGuesstimator = latencyGuesstimator,
    _frameOffsetGuesstimator = frameOffsetGuesstimator,
    _frameOffset = 0,
    _framesOfLatency = 0,
    _framesSinceSetInputs = 0,
    _framesUntilNextFlush = framesBetweenFlushes,
    _framesUntilNextPing = framesBetweenPings,
    _framesBetweenFlushes = framesBetweenFlushes,
    _framesBetweenPings = framesBetweenPings,
    _framesBetweenSmoothing = framesBetweenSmoothing,
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
      return self._hasSetInitialState and self._hasInitializedFrameOffset and self._hasInitializedLatency
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
        self:_buffer(constants.EVENT, event)
        -- Return the event
        return event
      end
    end,
    setInputs = function(self, inputs, params)
      params = params or {}
      params.isInputEvent = true
      params.maxFramesLate = params.maxFramesLate or 3
      params.maxFramesEarly = params.maxFramesEarly or 30
      if self._framesSinceSetInputs >= 12 or not self._cullRedundantEvents or not tableUtils.isEquivalent(inputs, self.game:getInputsForClient(self.clientId)) then
        self._framesSinceSetInputs = 0
        return self:fireEvent('set-inputs', {
          clientId = self.clientId,
          inputs = inputs
        }, params)
      end
    end,
    update = function(self, dt)
      self._clientTime = self._clientTime + dt
      -- Update the underlying messaging client
      self._messageClient:update(dt)
      self._latencyGuesstimator:update(dt)
      self._frameOffsetGuesstimator:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      self._clientFrame = self._clientFrame + 1
      self._framesSinceSetInputs = self._framesSinceSetInputs + 1
      -- Update the game (via the game runner)
      self._runner:moveForwardOneFrame(dt)
      self._runnerWithoutSmoothing:moveForwardOneFrame(dt)
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:moveForwardOneFrame(dt)
      end
      if self._messageClient:isConnected() then
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
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction.framesOfHistory = self._runnerWithoutSmoothing.framesOfHistory
      end
      -- Smooth game
      if self._framesBetweenSmoothing <= 0 or self._clientFrame % self._framesBetweenSmoothing == 0 then
        self:_smoothGame()
      end
    end,
    drawNetworkStats = function(self, x, y, width, height)
      -- Draw the latency and time offset side-by-side
      if width > 2 * height then
        self._latencyGuesstimator:draw(x, y, width / 2, height)
        self._frameOffsetGuesstimator:draw(x + width / 2, y, width / 2, height)
      -- Draw the latency and time offset stacked on one another
      else
        self._latencyGuesstimator:draw(x, y, width, height * 2 / 3)
        self._frameOffsetGuesstimator:draw(x, y + height * 2 / 3, width, height * 1 / 3)
      end
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
        if entity then
          return game:copyEntityProps(candidateEntity, entity)
        else
          return game:cloneEntity(candidateEntity)
        end
      else
        return entity
      end
    end,
    syncInputs = function(self, game, inputs, candidateInputs, isPrediction)
      if isPrediction then
        if inputs[self.clientId] and candidateInputs[self.clientId] then
          tableUtils.copyProps(candidateInputs[self.clientId], tableUtils.clearProps(inputs[self.clientId]))
        elseif candidateInputs[self.clientId] then
          inputs[self.clientId] = tableUtils.cloneTable(candidateInputs[self.clientId])
        else
          inputs[self.clientId] = nil
        end
      else
        for k, v in ipairs(inputs) do
          if k ~= self.clientId then
            if v and candidateInputs[k] then
              tableUtils.copyProps(candidateInputs[k], tableUtils.clearProps(v))
            else
              inputs[k] = nil
            end
          end
        end
        for k, v in ipairs(candidateInputs) do
          if k ~= self.clientId and not inputs[k] then
            inputs[k] = tableUtils.cloneTable(v)
          end
        end
      end
      return inputs
    end,
    syncData = function(self, game, data, candidateData, isPrediction)
      if isPrediction then
        return data
      else
        return tableUtils.copyProps(candidateData, tableUtils.clearProps(data))
      end
    end,
    smoothEntity = function(self, game, entity, idealEntity)
      if entity and idealEntity then
        return game:copyEntityProps(idealEntity, entity)
      elseif idealEntity then
        return game:cloneEntity(idealEntity)
      end
    end,
    smoothInputs = function(self, game, inputs, idealInputs)
      return tableUtils.copyProps(idealInputs, tableUtils.clearProps(inputs))
    end,
    smoothData = function(self, game, data, idealData)
      return tableUtils.copyProps(idealData, tableUtils.clearProps(data))
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
    _buffer = function(self, messageType, messageContent)
      self._messageClient:buffer(messageType, messageContent)
      -- Flush immediately if we have no auto-flushing
      if self._framesBetweenFlushes <= 0 then
        self._messageClient:flush()
      end
    end,
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
      local wasStable = self:isStable()
      self._frameOffsetGuesstimator:setFrameOffset(self._clientFrame - state.frame)
      self._hasSetInitialState = true
      self._framesUntilNextPing = 0
      self._framesUntilNextFlush = 0
      -- Set the state of the client-side game
      if self._runnerWithoutPrediction then
        self._runnerWithoutPrediction:reset()
        self._runnerWithoutPrediction:setState(tableUtils.cloneTable(state))
      end
      self._runnerWithoutSmoothing:reset()
      self._runnerWithoutSmoothing:setState(state)
      if not wasStable and self:isStable() then
        self:_handleStabilize()
      end
    end,
    _handleStabilize = function(self)
      for _, callback in ipairs(self._stabilizeCallbacks) do
        callback()
      end
    end,
    _handleDestabilize = function(self)
      local wasStable = self:isStable()
      self._hasSetInitialState = false
      if wasStable then
        for _, callback in ipairs(self._destabilizeCallbacks) do
          callback()
        end
      end
    end,
    _handleConnectFailure = function(self, reason)
      logger.info('Client failed to connect to server: ' .. (reason or 'No reason given'))
      -- Trigger connect failure callbacks
      for _, callback in ipairs(self._connectFailureCallbacks) do
        callback(reason or 'Failed to connect to server')
      end
    end,
    _handleDisconnect = function(self, reason)
      logger.info('Client ' .. self.clientId .. ' disconnected from server: ' .. (reason or 'No reason given') .. ' [frame=' .. self.game.frame .. ']')
      self._framesOfLatency = 0
      self._hasSetInitialState = false
      -- Trigger disconnect callbacks
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(reason or 'Connection terminated')
      end
    end,
    _handleReceive = function(self, messageType, messageContent)
      if messageType == constants.EVENT then
        self:_handleReceiveEvent(messageContent)
      elseif messageType == constants.REJECT_EVENT then
        self:_handleRejectEvent(messageContent)
      elseif messageType == constants.PING_RESPONSE then
        self:_handlePingResponse(messageContent)
      elseif messageType == constants.STATE_SNAPSHOT then
        self:_handleStateSnapshot(messageContent)
      end
    end,
    _handleReceiveEvent = function(self, event)
      if event.serverMetadata and event.serverMetadata.frame then
        self:_recordFrameOffset(event.serverMetadata.frame, 'event')
      end
      local preservedFrameAdjustment = 0
      if event.serverMetadata and event.serverMetadata.proposedEventFrame then
        preservedFrameAdjustment = event.frame - event.serverMetadata.proposedEventFrame
      end
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata, 'event')
      self:_applyEvent(event, { preservedFrameAdjustment = preservedFrameAdjustment }) -- TODO
    end,
    _handleRejectEvent = function(self, event)
      logger.debug('Client ' .. self.clientId .. ' "' .. event.type .. '" event on frame ' .. event.frame .. ' was rejected by server [frame=' .. self.game.frame .. ']')
      self:_recordLatencyOffset(event.clientMetadata, event.serverMetadata, 'rejection')
      self:_unapplyEvent(event)
    end,
    _handlePingResponse = function(self, ping)
      self:_recordFrameOffset(ping.frame, 'ping')
      self:_recordLatencyOffset(ping.clientMetadata, ping.serverMetadata, 'ping')
    end,
    _syncToTargetGame = function(self, sourceGame, targetGame, isPrediction)
      local entityIndex = {}
      local entities = {}
      -- Sync entities that exist in the target game
      local entityExistsInTargetGame = {}
      for _, targetEntity in ipairs(targetGame.entities) do
        local id = targetGame:getEntityId(targetEntity)
        entityExistsInTargetGame[id] = true
        local sourceEntity = sourceGame:getEntityById(id)
        local isSyncEnabled
        if sourceEntity then
          isSyncEnabled = sourceGame:isSyncEnabledForEntity(sourceEntity) and targetGame:isSyncEnabledForEntity(targetEntity)
        else
          isSyncEnabled = targetGame:isSyncEnabledForEntity(targetEntity)
        end
        if isSyncEnabled then
          local syncedEntity = self:syncEntity(sourceGame, sourceEntity, targetEntity, isPrediction)
          if syncedEntity then
            entityIndex[id] = syncedEntity
            table.insert(entities, syncedEntity)
          end
        end
      end
      -- Sync entities that don't exist in the target game
      for _, sourceEntity in ipairs(sourceGame.entities) do
        local id = sourceGame:getEntityId(sourceEntity)
        if not entityExistsInTargetGame[id] and sourceGame:isSyncEnabledForEntity(sourceEntity) then
          local syncedEntity = self:syncEntity(sourceGame, sourceEntity, nil, isPrediction)
          if syncedEntity then
            entityIndex[id] = syncedEntity
            table.insert(entities, syncedEntity)
          end
        end
      end
      -- Sync entities
      sourceGame.entities = entities
      sourceGame:reindexEntities(entityIndex)
      -- Sync data
      sourceGame.data = self:syncData(sourceGame, sourceGame.data, targetGame.data, isPrediction)
      -- Sync inputs
      sourceGame.inputs = self:syncInputs(sourceGame, sourceGame.inputs, targetGame.inputs, isPrediction)
    end,
    _handleStateSnapshot = function(self, state)
      if not self._hasSetInitialState then
        self:_setInitialState(state)
      else
        local frame = state.frame
        self:_recordFrameOffset(frame, 'snapshot')
        -- state represents what the game would currently look like with no client-side prediction
        if self._runnerWithoutPrediction then
          self._runnerWithoutPrediction:applyState(tableUtils.cloneTable(state))
        end
        local sourceGame = self.gameWithoutSmoothing
        local targetGame = self._gameDefinition:new({ initialState = state })
        -- Fix client-predicted inconsistencies in the past
        self._runnerWithoutSmoothing:applyStateTransform(frame - self._framesOfLatency, function(game)
          self:_syncToTargetGame(sourceGame, targetGame, true)
        end)
        -- Fix non-predicted inconsistencies in the present
        self._runnerWithoutSmoothing:applyStateTransform(frame, function(game)
          self:_syncToTargetGame(sourceGame, targetGame, false)
        end)
      end
    end,
    _smoothGame = function(self)
      local isStable = self._hasSetInitialState and self._hasInitializedFrameOffset and self._hasInitializedLatency
      local sourceGame = self.game
      local targetGame = self.gameWithoutSmoothing
      local entityIndex = {}
      local entities = {}
      -- Just copy the current frame
      sourceGame.frame = targetGame.frame
      -- Smooth entities
      local entityExistsInTargetGame = {}
      for _, targetEntity in ipairs(targetGame.entities) do
        local id = targetGame:getEntityId(targetEntity)
        entityExistsInTargetGame[id] = true
        local sourceEntity = sourceGame:getEntityById(id)
        local smoothedEntity
        if isStable or not sourceEntity then
          smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, targetEntity)
        else
          smoothedEntity = sourceEntity
        end
        if smoothedEntity then
          entityIndex[id] = smoothedEntity
          table.insert(entities, smoothedEntity)
        end
      end
      -- Sync entities that don't exist in the target game
      for _, sourceEntity in ipairs(sourceGame.entities) do
        local id = sourceGame:getEntityId(sourceEntity)
        if not entityExistsInTargetGame[id] then
          local smoothedEntity
          if isStable then
            smoothedEntity = self:smoothEntity(sourceGame, sourceEntity, nil)
          else
            smoothedEntity = sourceEntity
          end
          if smoothedEntity then
            entityIndex[id] = smoothedEntity
            table.insert(entities, smoothedEntity)
          end
        end
      end
      -- Smooth entities
      sourceGame.entities = entities
      sourceGame:reindexEntities(entityIndex)
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
      -- Send a ping to the server
      self:_buffer(constants.PING, self:_addClientMetadata({})) -- TODO
    end,
    _addClientMetadata = function(self, obj)
      obj.clientMetadata = {
        clientId = self.clientId,
        clientTimeSent = self._clientTime,
        clientFrameSent = self._clientFrame
      } -- TODO
      return obj
    end,
    _recordLatencyOffset = function(self, clientMetadata, serverMetadata, type)
      if clientMetadata and clientMetadata.clientId == self.clientId and clientMetadata.clientTimeSent then
        local time = self._clientTime - clientMetadata.clientTimeSent
        if not self._latencyGuesstimator:hasSetLatency() then
          self._latencyGuesstimator:setLatency(time + math.min(0.4, 0.5 * time))
        end
        self._latencyGuesstimator:record(time, type)
      end
    end,
    _recordFrameOffset = function(self, frame, type)
      self._frameOffsetGuesstimator:record(self._clientFrame - frame, type)
    end,
    _handleChangeLatency = function(self, latency, prevLatency)
      local wasStable = self:isStable()
      local clientLabel = self.clientId and ('Client ' .. self.clientId) or 'Client'
      local framesOfLatency = math.ceil(60 * latency + 1)
      if not prevLatency then
        logger.debug(clientLabel .. ' initializing latency to ' .. framesOfLatency .. ' frames [frame=' .. self.game.frame .. ']')
      else
        local change = framesOfLatency - self._framesOfLatency
        if change ~= 0 then
          logger.debug(clientLabel .. ' adjusting latency from ' .. self._framesOfLatency .. ' to ' .. framesOfLatency .. ' frames (' .. (change >= 0 and '+' .. change or change) .. ') [frame=' .. self.game.frame .. ']')
        end
      end
      self._framesOfLatency = framesOfLatency
      self._hasInitializedLatency = true
      if not wasStable and self:isStable() then
        self:_handleStabilize()
      end
    end,
    _handleChangeFrameOffset = function(self, offset, prevOffset)
      local wasStable = self:isStable()
      local clientLabel = self.clientId and ('Client ' .. self.clientId) or 'Client'
      local frameOffset = math.ceil(offset + 1)
      if not prevOffset then
        logger.debug(clientLabel .. ' initializing frame offset to ' .. (frameOffset >= 0 and '+' .. frameOffset or frameOffset) .. ' frames [frame=' .. self.game.frame .. ']')
      else
        local change = frameOffset - self._frameOffset
        if change ~= 0 then
          logger.debug(clientLabel .. ' adjusting frame offset from ' .. (self._frameOffset >= 0 and '+' .. self._frameOffset or self._frameOffset) .. ' to ' .. (frameOffset >= 0 and '+' .. frameOffset or frameOffset) .. ' frames (' .. (change >= 0 and '+' .. change or change) .. ') [frame=' .. self.game.frame .. ']')
        end
      end
      local frameOffsetAdjustment = self._frameOffset - frameOffset
      self._frameOffset = frameOffset
      self._hasInitializedFrameOffset = true
      if self._hasSetInitialState then
        -- Fast forward if we're behind the states the server is sending us
        if frameOffsetAdjustment > 90 then
          logger.info(clientLabel .. ' destabilized due to being too far behind the server [frame=' .. self.game.frame .. ']')
          self:_handleDestabilize()
        elseif frameOffsetAdjustment > 0 then
          logger.debug(clientLabel .. ' fast forwarding ' .. frameOffsetAdjustment .. ' frames to sync with server [frame=' .. self.game.frame .. ']')
          local fastForwardSuccessful = self._runnerWithoutSmoothing:fastForward(frameOffsetAdjustment)
          if self._runnerWithoutPrediction then
            fastForwardSuccessful = fastForwardSuccessful and self._runnerWithoutPrediction:fastForward(frameOffsetAdjustment)
          end
          if not fastForwardSuccessful then
            logger.info(clientLabel .. ' destabilized due to failed fast forward [frame=' .. self.game.frame .. ']')
            self:_handleDestabilize()
          end
        -- Rewind if we're ahead of the states the server is sending us
        elseif frameOffsetAdjustment < -90 then
          logger.info(clientLabel .. ' destabilized due to being too far ahead of the server [frame=' .. self.game.frame .. ']')
          self:_handleDestabilize()
        elseif frameOffsetAdjustment < 0 then
          logger.debug(clientLabel .. ' rewinding ' .. (-frameOffsetAdjustment) .. ' frames to sync with server [frame=' .. self.game.frame .. ']')
          local rewindSuccessful = self._runnerWithoutSmoothing:rewind(-frameOffsetAdjustment)
          if self._runnerWithoutPrediction then
            rewindSuccessful = rewindSuccessful and self._runnerWithoutPrediction:rewind(-frameOffsetAdjustment)
          end
          if not rewindSuccessful then
            logger.info(clientLabel .. ' destabilized due to failed rewind [frame=' .. self.game.frame .. ']')
            self:_handleDestabilize()
          end
        end
      end
      if not wasStable and self:isStable() then
        self:_handleStabilize()
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
  messageClient:onReceive(function(messageType, messageContent)
    client:_handleReceive(messageType, messageContent)
  end)
  latencyGuesstimator:onChangeLatency(function(latency, prevLatency)
    client:_handleChangeLatency(latency, prevLatency)
  end)
  frameOffsetGuesstimator:onChangeFrameOffset(function(offset, prevOffset)
    client:_handleChangeFrameOffset(offset, prevOffset)
  end)

  return client
end

return GameClient
