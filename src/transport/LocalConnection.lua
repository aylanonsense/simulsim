local logger = require 'src/utils/logger'

local LocalConnection = {}
function LocalConnection:new(params)
  params = params or {}
  local isClient = params.isClient or false
  local sendStream = params.sendStream
  local receiveStream = params.receiveStream
  local latencySpikeChance = params.latencySpikeChance or 0.00

  local conn = {
    -- Private vars
    _isConnected = false,
    _isClient = isClient,
    _sendStream = sendStream,
    _receiveStream = receiveStream,
    _latencySpikeChance = latencySpikeChance,
    _timeUntilLatencySpikeCheck = 0.00,
    _connectCallbacks = {},
    _disconnectCallbacks = {},
    _receiveCallbacks = {},

    -- Public methods
    connect = function(self)
      self._sendStream:send({ 'connect-request' }, true)
    end,
    disconnect = function(self)
      self._isConnected = false
      self._sendStream:send({ 'disconnected' }, true)
      for _, callback in ipairs(self._disconnectCallbacks) do
        callback()
      end
    end,
    isConnected = function(self)
      return self._isConnected
    end,
    send = function(self, msg)
      self._sendStream:send({ 'message', msg })
    end,
    update = function(self, dt)
      if self._latencySpikeChance > 0.00 then
        self._timeUntilLatencySpikeCheck = self._timeUntilLatencySpikeCheck - dt
        if self._timeUntilLatencySpikeCheck <= 0.00 then
          if math.random() >= self._latencySpikeChance then
            self._sendStream:stopLatencySpike()
            self._receiveStream:stopLatencySpike()
          else
            logger.debug('Simulating latency spike for the next 5 seconds')
            self._sendStream:startLatencySpike()
            self._receiveStream:startLatencySpike()
          end
          self._timeUntilLatencySpikeCheck = 5.00
        end
      end
    end,
    simulateNetworkConditions = function(self, params)
      params = params or {}
      local sendParams = {}
      local receiveParams = {}
      -- Divide latency between the send transport layer and the receive transport layer
      if params.latency then
        sendParams.latency = params.latency / 2
        receiveParams.latency = params.latency / 2
      end
      if params.latencyDeviation then
        sendParams.latencyDeviation = params.latencyDeviation / 2
        receiveParams.latencyDeviation = params.latencyDeviation / 2
      end
      if params.packetLossChance then
        sendParams.packetLossChance = params.packetLossChance
        receiveParams.packetLossChance = params.packetLossChance
      end
      if params.latencySpikeChance then
        self._latencySpikeChance = params.latencySpikeChance
      end
      self._sendStream:simulateNetworkConditions(sendParams)
      self._receiveStream:simulateNetworkConditions(receiveParams)
    end,

    -- Callback methods
    onConnect = function(self, callback)
      table.insert(self._connectCallbacks, callback)
    end,
    onDisconnect = function(self, callback)
      table.insert(self._disconnectCallbacks, callback)
    end,
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end,

    -- Private methods
    _handlePacket = function(self, packetType, packetContent)
      -- Server accepts connection requests
      if packetType == 'connect-request' and not self._isClient then
        self._isConnected = true
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
        end
        self._sendStream:send({ 'connect-accept' }, true)
      -- Client connects to the server
      elseif packetType == 'connect-accept' and self._isClient then
        self._isConnected = true
        for _, callback in ipairs(self._connectCallbacks) do
          callback()
        end
      elseif packetType == 'disconnected' then
        self._isConnected = false
        for _, callback in ipairs(self._disconnectCallbacks) do
          callback()
        end
      elseif packetType == 'message' then
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(packetContent)
        end
      end
    end
  }

  -- Bind events
  conn._receiveStream:onReceive(function(packet)
    conn:_handlePacket(packet[1], packet[2])
  end)

  -- Return the new connection
  return conn
end

return LocalConnection
