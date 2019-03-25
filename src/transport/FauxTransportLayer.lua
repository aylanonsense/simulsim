local TransportLayer = {}
function TransportLayer:new(params)
  local transportLayer = {
    -- Private config vars
    _latency = params and params.latency or 0,
    _latencyDeviation = params and params.latencyDeviation or 0,
    _packetLossChance = params and params.packetLossChance or 0,

    -- Private vars
    _packets = {},
    _receiveCallbacks = {},

    -- Public methods
    send = function(self, msg, unlosable)
      local timeUntilReceive = (self._latency + self._latencyDeviation * (2 * math.random() - 1)) / 1000
      -- Receive the message immediately
      if timeUntilReceive <= 0 then
        self:_handleReceive(msg, unlosable)
      -- Or schedule it to be received later
      else
        table.insert(self._packets, {
          message = msg,
          timeUntilReceive = timeUntilReceive,
          unlosable = unlosable or false
        })
      end
    end,
    update = function(self, dt)
      -- Figure out which messages are ready to be received
      local packetsToSend = {}
      for i = #self._packets, 1, -1 do
        self._packets[i].timeUntilReceive = self._packets[i].timeUntilReceive - dt
        if self._packets[i].timeUntilReceive < 0 then
          table.insert(packetsToSend, self._packets[i])
          table.remove(self._packets, i)
        end
      end
      -- Receive those messages
      for i = #packetsToSend, 1, -1 do
        self:_handleReceive(packetsToSend[i].message, packetsToSend[i].unlosable)
      end
    end,

    -- Private methods
    _handleReceive = function(self, msg, unlosable)
      if unlosable or math.random() >= self._packetLossChance then
        for _, callback in ipairs(self._receiveCallbacks) do
          callback(msg)
        end
      end
    end,

    -- Callback methods
    onReceive = function(self, callback)
      table.insert(self._receiveCallbacks, callback)
    end
  }

  -- Return the new transport layer
  return transportLayer
end

return TransportLayer
