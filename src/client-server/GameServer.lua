-- Load dependencies
local MessageServer = require 'src/client-server/MessageServer'
local GameRunner = require 'src/game/GameRunner'
local stringUtils = require 'src/utils/string'
local logger = require 'src/utils/logger'

local ServerSideGameClient = {}

function ServerSideGameClient:new(params)
  params = params or {}
  local server = params.server
  local clientId = params.clientId
  local connId = params.connId
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenSnapshots = params.framesBetweenSnapshots or 35

  return {
    -- Private vars
    _server = server,
    _messageServer = server._messageServer,
    _connId = connId,
    _framesUntilNextFlush = 0,
    _framesUntilNextSnapshot = 0,
    _disconnectCallbacks = {},
    _framesBetweenFlushes = framesBetweenFlushes,
    _framesBetweenSnapshots = framesBetweenSnapshots,

    -- Public vars
    clientId = clientId,
    data = {},

    -- Public methods
    -- Disconnect a client that's connected to the server
    disconnect = function(self, reason)
      self._messageServer:disconnect(self._connId, reason)
    end,
    -- Returns true if the client's connection has been accepted by the server
    isConnected = function(self)
      return self._messageServer:isConnected(self._connId)
    end,
    update = function(dt) end,
    moveForwardOneFrame = function(self, dt)
      -- Send a snapshot of the game state every so often
      if self._framesBetweenSnapshots > 0 then
        self._framesUntilNextSnapshot = self._framesUntilNextSnapshot - 1
        if self._framesUntilNextSnapshot <= 0 then
          self._framesUntilNextSnapshot = self._framesBetweenSnapshots
          self:_sendStateSnapshot()
        end
      end
      -- Flush the client's messages every so often
      if self._framesBetweenFlushes > 0 then
        self._framesUntilNextFlush = self._framesUntilNextFlush - 1
        if self._framesUntilNextFlush <= 0 then
          self._framesUntilNextFlush = self._framesBetweenFlushes
          self._messageServer:flush(self._connId)
        end
      end
    end,

    -- Private methods
    _handleDisconnect = function(self, reason)
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback(reason)
      end
    end,
    _sendStateSnapshot = function(self)
      self._messageServer:buffer(self._connId, { 'state-snapshot', self._server:generateStateSnapshotForClient(self) })
    end,
    _sendPingResponse = function(self, pingResponse)
      self._messageServer:buffer(self._connId, { 'ping-response', pingResponse })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,
    _sendEvent = function(self, event, params)
      self._messageServer:buffer(self._connId, { 'event', event })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,
    -- Rejects an event that came from this client
    _rejectEvent = function(self, event)
      self._messageServer:buffer(self._connId, { 'reject-event', event })
      if self._framesBetweenFlushes <= 0 then
        self._messageServer:flush(self._connId)
      end
    end,

    -- Callback methods
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end
  }
end

-- The server, which manages connected clients
local GameServer = {}
function GameServer:new(params)
  params = params or {}
  local listener = params.listener
  local gameDefinition = params.gameDefinition
  local framesBetweenFlushes = params.framesBetweenFlushes or 2
  local framesBetweenSnapshots = params.framesBetweenSnapshots or 35
  local maxClientEventFramesLate = params.maxClientEventFramesLate or 0
  local maxClientEventFramesEarly = params.maxClientEventFramesEarly or 45

  -- Create the game
  local runner = GameRunner:new({
    game = gameDefinition:new(),
    framesOfHistory = maxClientEventFramesLate + 1,
    isRenderable = false
  })

  -- Wrap the listener in a message server to make it easier to work with
  local messageServer = MessageServer:new({
    listener = listener
  })

  local server = {
    -- Private vars
    _messageServer = messageServer,
    _nextClientId = 1,
    _clients = {},
    _runner = runner,
    _framesBetweenFlushes = framesBetweenFlushes,
    _framesBetweenSnapshots = framesBetweenSnapshots,
    _maxClientEventFramesLate = maxClientEventFramesLate,
    _maxClientEventFramesEarly = maxClientEventFramesEarly,
    _connectCallbacks = {},

    -- Public vars
    game = runner.game,

    -- Public methods
    -- Starts the server listening for new client connections
    startListening = function(self)
      self._messageServer:startListening()
    end,
    -- Returns true if the server is listening for new client connections
    isListening = function(self)
      return self._messageServer:isListening()
    end,
    -- Gets a client with the given id
    getClientById = function(self, clientId)
      for _, client in ipairs(self._clients) do
        if client.clientId == clientId then
          return client
        end
      end
    end,
    -- Gets the clients that are currently connected to the server
    getClients = function(self)
      return self._clients
    end,
    -- Fires an event for the game and lets all clients know
    fireEvent = function(self, eventType, eventData, params)
      -- Create an event
      local event = self:_addServerMetadata({
        id = 'server-' .. stringUtils.generateRandomString(10),
        frame = self.game.frame + 1,
        type = eventType,
        data = eventData
      })
      -- Apply the event server-side and let the clients know about it
      self:_applyEvent(event, params)
      -- Return the event
      return event
    end,
    getGame = function(self)
      return self.game
    end,
    update = function(self, dt)
      -- Update the underlying messaging server
      self._messageServer:update(dt)
      -- Update all clients
      for _, client in ipairs(self._clients) do
        client:update(dt)
      end
    end,
    moveForwardOneFrame = function(self, dt)
      -- Update the game via the game runner
      self._runner:moveForwardOneFrame(dt)
      -- Update all clients
      for _, client in ipairs(self._clients) do
        client:moveForwardOneFrame(dt)
      end
    end,

    -- Overridable methods
    -- Call accept with client data you'd like to give to the client, or reject with a reason for rejection
    handleConnectRequest = function(self, client, handshake, accept, reject)
      accept()
    end,
    -- By default the server sends every event to all clients
    shouldSendEventToClient = function(self, client, event)
      return true
    end,
    -- By default the server is entirely trusting
    shouldAcceptEventFromClient = function(self, client, event)
      return true
    end,
    generateStateSnapshotForClient = function(self, client)
      return self.game:getState()
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,

    -- Private methods
    _getClientByConnId = function(self, connId)
      for i = 1, #self._clients do
        if self._clients[i]._connId == connId then
          return self._clients[i], i
        end
      end
    end,
    _addServerMetadata = function(self, obj)
      obj.serverMetadata = {
        frame = self.game.frame
      }
      return obj
    end,
    _handleConnectRequest = function(self, connId, handshake, accept, reject)
      -- Create a new client
      local clientId = self._nextClientId
      self._nextClientId = self._nextClientId + 1
      local client = ServerSideGameClient:new({
        server = self,
        clientId = clientId,
        connId = connId,
        framesBetweenFlushes = self._framesBetweenFlushes,
        framesBetweenSnapshots = self._framesBetweenSnapshots
      })
      local accept2 = function(clientData)
        logger.info('Server accepted connection from client ' .. clientId .. ' [frame=' .. self.game.frame .. ']')
        -- Add the client data
        client.data = clientData
        -- Insert the client into the list of clients
        table.insert(self._clients, client)
        -- Accept the connection
        accept({ clientId, clientData or {}, self:generateStateSnapshotForClient(client) })
        -- Trigger connect callbacks
        for _, callback in ipairs(self._connectCallbacks) do
          callback(client)
        end
      end
      local reject2 = function(reason)
        logger.info('Server rejected connection from client ' .. clientId .. ': ' .. (reason or 'No reason given') .. ' [frame=' .. self.game.frame .. ']')
        reject(reason)
      end
      self:handleConnectRequest(client, handshake, accept2, reject2)
    end,
    _handleDisconnect = function(self, connId, reason)
      local client, i = self:_getClientByConnId(connId)
      if client then
        logger.info('Server disconnecting client ' .. client.clientId .. ': ' .. (reason or 'No reason given') .. ' [frame=' .. self.game.frame .. ']')
        -- Remove the client
        table.remove(self._clients, i)
        -- Trigger the client's disconnect callbacks
        client:_handleDisconnect(reason or 'Connection terminated')
      end
    end,
    _handleReceive = function(self, connId, messageType, messageContent)
      local client = self:_getClientByConnId(connId)
      if client then
        if messageType == 'event' then
          -- Add some metadata onto the event recording the fact that it was received
          local event = self:_addServerMetadata(messageContent)
          local eventApplied = false
          if self:shouldAcceptEventFromClient(client, event) then
            local frameOffset = event.frame - self.game.frame - 1 -- positive is early, negative is late
            local maxFramesEarly = self._maxClientEventFramesEarly
            local maxFramesLate = self._maxClientEventFramesLate
            if event.clientMetadata then
              if event.clientMetadata.maxFramesLate then
                maxFramesLate = event.clientMetadata.maxFramesLate
              end
              if event.clientMetadata.maxFramesEarly then
                maxFramesEarly = event.clientMetadata.maxFramesEarly
              end
            end
            local isTooEarly = (frameOffset > maxFramesEarly)
            local isTooLate = ((-frameOffset) > maxFramesLate)
            if not isTooEarly and not isTooLate then
              if event.isInputEvent and event.type == 'set-inputs' and self.game.frameOfLastInput[client.clientId] and self.game.frameOfLastInput[client.clientId] > event.frame then
                logger.silly('Server rejecting "' .. event.type .. '" event from client ' .. client.clientId .. ' because newer inputs have already been applied [frame=' .. self.game.frame .. ']')
              else
                event.serverMetadata.proposedEventFrame = event.frame
                -- Apply the event server-side and let all clients know about it
                if (frameOffset <= 0 or (frameOffset > 0 and event.clientMetadata and event.clientMetadata.applyImmediatelyWhenEarly)) and event.frame ~= self.game.frame + 1 then
                  logger.silly('Server adjusting "' .. event.type .. '" event from client ' .. client.clientId .. ' from frame=' .. event.frame .. ' to ' .. (self.game.frame + 1) .. ' [frame=' .. self.game.frame .. ']')
                  event.frame = self.game.frame + 1
                end
                eventApplied = self:_applyEvent(event)
                if not eventApplied then
                  logger.silly('Server failed to apply "' .. event.type .. '" event from client ' .. client.clientId .. ' [frame=' .. self.game.frame .. ']')
                end
              end
            else
              logger.silly('Server rejecting "' .. event.type .. '" event from client ' .. client.clientId .. ' because it was ' .. math.abs(frameOffset) .. ' ' .. (math.abs(frameOffset) == 1 and 'frame' or 'frames') .. ' ' .. (isTooEarly and 'too early' or 'too late') .. ' [frame=' .. self.game.frame .. ']')
            end
          end
          if not eventApplied then
            -- Let the client know that their event was rejected or wasn't able to be applied
            client:_rejectEvent(event)
          end
        elseif messageType == 'ping' then
          local pingResponse = self:_addServerMetadata(messageContent)
          pingResponse.frame = self.game.frame
          client:_sendPingResponse(pingResponse)
        end
      end
    end,
    _applyEvent = function(self, event, params)
      -- Apply the event server-side
      if self._runner:applyEvent(event) then
        -- Let all clients know about the event
        for _, client in ipairs(self._clients) do
          if self:shouldSendEventToClient(client, event) then
            client:_sendEvent(event)
          end
        end
        return true
      else
        return false
      end
    end
  }

  -- Bind events
  messageServer.handleConnectRequest = function(self, connId, handshake, accept, reject)
    server:_handleConnectRequest(connId, handshake, accept, reject)
  end
  messageServer:onDisconnect(function(connId, reason)
    server:_handleDisconnect(connId, reason)
  end)
  messageServer:onReceive(function(connId, msg)
    server:_handleReceive(connId, msg[1], msg[2])
  end)

  return server
end

return GameServer
