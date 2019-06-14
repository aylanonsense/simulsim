local network = {
  _packets = {},
  load = function(self) end,
  update = function(self, dt)
    for  i = #self._packets, 1, -1 do
      local packet = self._packets[i]
      packet.timeUntilReceive = packet.timeUntilReceive - dt
      if packet.timeUntilReceive <= 0 then
        table.remove(self._packets, i)
        self:onReceive(packet.message)
      end
    end
  end,
  send = function(self, message)
    local latency = 0.05 + 0.1 * math.random()
    table.insert(self._packets, {
      message = message,
      timeUntilReceive = latency
    })
  end,
  onReceive = function(self, message) end
}

local pinger = {
  _network = nil,
  _frame = 0,
  _time = 0.00,
  _timeToNextPing = 0.00,
  records = {},
  load = function(self, network)
    self._network = network
    self._network.onReceive = function(network, message)
      table.insert(self.records, {
        sendFrame = message.sendFrame,
        sendTime = message.sendTime,
        receiveFrame = self._frame,
        receiveTime = self._time,
        latency = self._time - message.sendTime,
        framesOfLatency = self._frame - message.sendFrame
      })
    end
  end,
  update = function(self, dt)
    self._frame = self._frame + 1
    self._time = self._time + dt
    self._timeToNextPing = self._timeToNextPing - dt
    if self._timeToNextPing < 0 then
      self._timeToNextPing = 0.1
      self._network:send({
        sendFrame = self._frame,
        sendTime = self._time
      })
    end
  end
}

function love.load()
  network:load()
  pinger:load(network)
end

function love.update(dt)
  network:update(dt)
  pinger:update(dt)
end

function love.draw()
  love.graphics.clear(0, 0, 0)
  love.graphics.setColor(0.5, 0.5, 1)
  for _, record in ipairs(pinger.records) do
    love.graphics.line(200 * record.sendTime, 10, 200 * record.receiveTime, 100)
  end
end
