local transportLayers = {}

local TransportLayer = {}
function TransportLayer:new(params)
  params = params or {}

  -- Config params
  local latency = params.latency or 0 -- ms
  local latencyDeviation = params.latencyDeviation or 0 -- ms
  local packetLossChance = params.packetLossChance or 0

  -- Private vars
  local packets = {}
  local receiveCallbacks = {}

  -- Private API
  local receive = function(self, msg, unlosable)
    if unlosable or math.random() >= packetLossChance then
      for _, callback in ipairs(receiveCallbacks) do
        callback(msg)
      end
    end
  end

  -- Public API
  local transportLayer = {
    send = function(self, msg, unlosable)
      local timeUntilReceive = (latency - latencyDeviation + 2 * latencyDeviation * math.random()) / 1000
      -- Receive the message immediately
      if timeUntilReceive <= 0 then
        receive(self, msg, unlosable)
      -- Or schedule it to be received later
      else
        table.insert(packets, {
          message = msg,
          timeUntilReceive = timeUntilReceive,
          unlosable = unlosable or false
        })
      end
    end,
    update = function(self, dt)
      -- Figure out which messages are ready to be received
      local packetsToSend = {}
      for i = #packets, 1, -1 do
        packets[i].timeUntilReceive = packets[i].timeUntilReceive - dt
        if packets[i].timeUntilReceive < 0 then
          table.insert(packetsToSend, packets[i])
          table.remove(packets, i)
        end
      end
      -- Receive those messages
      for i = #packetsToSend, 1, -1 do
        receive(self, packetsToSend[i].message, packetsToSend[i].unlosable)
      end
    end,
    onReceive = function(self, callback)
      table.insert(receiveCallbacks, callback)
    end
  }

  -- Add to static array of transport layers
  table.insert(transportLayers, transportLayer)

  -- Return the new transport layer
  return transportLayer
end

-- Updates all tranport layers that have been instantiated
function TransportLayer:updateAll(dt)
  for _, transportLayer in ipairs(transportLayers) do
    transportLayer:update(dt)
  end
end

return TransportLayer
