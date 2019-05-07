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
  local framesBetweenFlushes = params.framesBetweenFlushes or 3
  local framesBetweenPings = params.framesBetweenPings or 15
  local maxFramesOfLatency = params.maxFramesOfLatency or 180

  -- Create a game for the client and a runner for it
  local clientRunner = GameRunner:new({
    game = gameDefinition:new()
  })
  local serverRunner = GameRunner:new({
    game = gameDefinition:new()
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
  local messageClient = MessageClient:new({
    conn = conn
  })

  local client = {
    -- Private vars
    _hasSyncedTime = false,
    _hasSyncedLatency = false,
    _messageClient = messageClient,
    _clientRunner = clientRunner,
    _serverRunner = serverRunner,
    _timeSyncOptimizer = timeSyncOptimizer,
    _latencyOptimizer = latencyOptimizer,
    _framesOfLatency = 0,
    _syncId = nil,
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
    fireEvent = function(self, eventType, eventData, params)
      params = params or {}
      local isInputEvent = params.isInputEvent
      local predictClientSide = params.predictClientSide ~= false
      if self._messageClient:isConnected() then
        -- Create a new event
        local event = self:_addClientMetadata({
          id = 'client-' .. self.clientId .. '-' .. stringUtils.generateRandomString(10),
          frame = self._clientRunner:getGame().frame + self._framesOfLatency + 1,
          type = eventType,
          data = eventData,
          isInputEvent = isInputEvent
        })
        -- Apply a prediction of the event
        if predictClientSide then
          local serverEvent = tableUtils.cloneTable(event)
          self._serverRunner:applyEvent(serverEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5
          })
          local clientEvent = tableUtils.cloneTable(event)
          clientEvent.frame = self._clientRunner:getGame().frame + 1
          self._clientRunner:applyEvent(clientEvent, {
            framesUntilAutoUnapply = self._framesOfLatency + 5,
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
    getGame = function(self)
      return self._clientRunner:getGame()
    end,
    getGameWithoutPrediction = function(self)
      return self._serverRunner:getGame()
    end,
    update = function(self, dt)
      -- Update the underlying messaging client
      self._messageClient:update(dt)
    end,
    moveForwardOneFrame = function(self, dt)
      local wasSynced = self._hasSyncedTime and self._hasSyncedLatency
      -- Update the game (via the game runner)
      self._clientRunner:moveForwardOneFrame(dt)
      self._serverRunner:moveForwardOneFrame(dt)
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
              local fastForward1Successful = self._clientRunner:fastForward(timeAdjustment)
              local fastForward2Successful = self._serverRunner:fastForward(timeAdjustment)
              if not fastForward1Successful or not fastForward2Successful then
                self:_handleDesync()
              end
            elseif timeAdjustment < 0 then
              local rewind1Successful = self._clientRunner:rewind(-timeAdjustment)
              local rewind2Successful = self._serverRunner:rewind(-timeAdjustment)
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
      if self._clientRunner.framesOfHistory > math.max(self._framesOfLatency + 10, 30) then
        self._clientRunner.framesOfHistory = self._clientRunner.framesOfHistory - 1
      else
        self._clientRunner.framesOfHistory = math.min(self._framesOfLatency + 10, 300)
      end
      self._serverRunner.framesOfHistory = self._clientRunner.framesOfHistory
    end,
    simulateNetworkConditions = function(self, params)
      self._messageClient:simulateNetworkConditions(params)
    end,
    getFramesOfLatency = function(self)
      return self._framesOfLatency
    end,
    isEntityUsingClientSidePrediction = function(self, entity)
      return entity.clientId == self.clientId
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
      self._clientRunner:reset()
      self._clientRunner:setState(state)
      self._serverRunner:reset()
      self._serverRunner:setState(state)
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
      self.clientId = nil
      self.data = {}
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
    _handleStateSnapshot = function(self, state)
      if not self._hasSyncedTime then
        self:_syncWithState(state)
      else
        self:_recordTimeSyncOffset(state.frame)
        -- state represents what the game would currently look like with no client-side prediction
        self._serverRunner:applyState(state)
        -- Create a new game from the snapshot
        local snapshotGame = gameDefinition:new()
        snapshotGame:setState(state)
        self.lastSnapshot = snapshotGame -- DEBUG
        -- Fix client-predicted inconsistencies in the past
        self._clientRunner:applyStateTransform(snapshotGame.frame - self._framesOfLatency, function(game)
          -- Apply client's inputs to past state
          game.inputs[self.clientId] = tableUtils.cloneTable(snapshotGame.inputs[self.clientId])
          -- Apply client-predicted entity states to past state
          local entityExists = {}
          for _, entity in ipairs(snapshotGame.entities) do
            if self:isEntityUsingClientSidePrediction(entity) then
              local id = snapshotGame:getEntityId(entity)
              entityExists[id] = true
              local entity2, index = game:getEntityById(id)
              -- Replace entity states
              if entity2 then
                if game:isSyncEnabledForEntity(entity2) and snapshotGame:isSyncEnabledForEntity(entity) then
                  game.entities[index] = game:createEntityFromState(snapshotGame:getStateFromEntity(entity))
                end
              -- Spawn missing entities
              else
                if snapshotGame:isSyncEnabledForEntity(entity) then
                  table.insert(game.entities, game:createEntityFromState(snapshotGame:getStateFromEntity(entity)))
                end
              end
            end
          end
          -- Despawn client-predicted entities that shouldn't exist
          for i = #game.entities, 1, -1 do
            local id = game:getEntityId(game.entities[i])
            if self:isEntityUsingClientSidePrediction(game.entities[i]) and not entityExists[id] and game:isSyncEnabledForEntity(game.entities[i]) then
              table.remove(game.entities, i)
            end
          end
        end)
        -- Fix non-predicted inconsistencies in the present
        self._clientRunner:applyStateTransform(snapshotGame.frame, function(game)
          -- Apply non-predicted inputs to past state
          local clientPredictedInputs = game.inputs[self.clientId]
          game.inputs = tableUtils.cloneTable(snapshotGame.inputs)
          game.inputs[self.clientId] = clientPredictedInputs
          -- Apply non-predicted entity states to past state
          local entityExists = {}
          for _, entity in ipairs(snapshotGame.entities) do
            if not self:isEntityUsingClientSidePrediction(entity) then
              local id = snapshotGame:getEntityId(entity)
              entityExists[id] = true
              local entity2, index = game:getEntityById(id)
              -- Replace entity states
              if entity2 then
                if game:isSyncEnabledForEntity(entity2) then
                  game.entities[index] = game:createEntityFromState(snapshotGame:getStateFromEntity(entity))
                end
              -- Spawn missing entities
              else
                if snapshotGame:isSyncEnabledForEntity(entity) then
                  table.insert(game.entities, game:createEntityFromState(snapshotGame:getStateFromEntity(entity)))
                end
              end
            end
          end
          -- Despawn non-predicted entities that shouldn't exist
          for i = #game.entities, 1, -1 do
            local id = game:getEntityId(game.entities[i])
            if not self:isEntityUsingClientSidePrediction(game.entities[i]) and not entityExists[id] and game:isSyncEnabledForEntity(game.entities[i]) then
              table.remove(game.entities, i)
            end
          end
        end)
      end
    end,
    _applyEvent = function(self, event)
      self._serverRunner:applyEvent(event)
      return self._clientRunner:applyEvent(event)
    end,
    _unapplyEvent = function(self, event)
      self._serverRunner:unapplyEvent(event)
      return self._clientRunner:unapplyEvent(event)
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
      local frame = self._clientRunner:getGame().frame
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
        self._timeSyncOptimizer:recordOffset(frame - self._clientRunner:getGame().frame - 1)
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
