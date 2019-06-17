local LatencyGuesstimator = {}

-- local FONT = love.graphics.newFont(8)
local LATENCY_WINDOW = 12.00
local LOWER_LATENCY_WEIGHT = 0.2
local RAISE_LATENCY_WEIGHT = 0.05

function LatencyGuesstimator:new(params)
  params = params or {}

  return {
    _time = 0.00,
    _lastLatencyChangeTime = 0.00,
    _latencyHistory = {},
    _latencyGuessHistory = { { latency = 0.5, startTime = 0.00 } },
    _bestLowerLatency = nil,
    _bestLowerLatencyDuration = nil,
    _bestHigherLatency = nil,
    _bestHigherLatencyDuration = nil,
    -- _reluctance = 0.00,
    update = function(self, dt)
      self._time = self._time + dt
      -- self._reluctance = math.max(0, self._reluctance - dt - 0.01 * self._reluctance)
      local latency = self:getLatency()
      -- Calculate what the best latency would be to lower to
      local lowerLatency
      local lowerLatencyDuration
      local isFindingLowerLatencies = true
      self._bestLowerLatency = nil
      self._bestLowerLatencyDuration = nil
      self._bestHigherLatency = nil
      self._bestHigherLatencyDuration = nil
      for i = #self._latencyHistory, 1, -1 do
        local record = self._latencyHistory[i]
        if record.time > self._time - LATENCY_WINDOW and record.time > self._lastLatencyChangeTime then
          -- Find higher latencies
          if record.latency >= latency then
            isFindingLowerLatencies = false
            if not self._bestHigherLatency or record.latency >= self._bestHigherLatency then
              self._bestHigherLatency = record.latency
              self._bestHigherLatencyDuration = self._time - record.time
            elseif record.latency * 1.02 >= self._bestHigherLatency then
              self._bestHigherLatencyDuration = self._time - record.time
            end
          -- Find lower latencies
          elseif isFindingLowerLatencies then
            if not lowerLatency then
              lowerLatency = record.latency
            elseif record.latency > lowerLatency then
              if not self._bestLowerLatency or (latency - self._bestLowerLatency) * self._bestLowerLatencyDuration < (latency - lowerLatency) * lowerLatencyDuration then
                self._bestLowerLatency = lowerLatency
                self._bestLowerLatencyDuration = lowerLatencyDuration
              end
              lowerLatency = record.latency
            end
            lowerLatencyDuration = self._time - record.time
          end
        end
      end
      if lowerLatency and (not self._bestLowerLatency or (latency - self._bestLowerLatency) * self._bestLowerLatencyDuration < (latency - lowerLatency) * lowerLatencyDuration)then
        self._bestLowerLatency = lowerLatency
        self._bestLowerLatencyDuration = lowerLatencyDuration
      end
      if self._bestHigherLatency and (self._bestHigherLatency + 0.001 - latency) * self._bestHigherLatencyDuration > RAISE_LATENCY_WEIGHT then
        self:_setLatency(self._bestHigherLatency + 0.001)
        self._bestHigherLatency = nil
        self._bestHigherLatencyDuration = nil
      elseif self._bestLowerLatency and self._bestLowerLatencyDuration > 1.00 and (self._bestLowerLatencyDuration >= LATENCY_WINDOW - 0.50 or (latency - self._bestLowerLatency) * self._bestLowerLatencyDuration > LOWER_LATENCY_WEIGHT) then
        if latency - self._bestLowerLatency > 0.008 then
          self:_setLatency(self._bestLowerLatency)
          self._bestLowerLatency = nil
          self._bestLowerLatencyDuration = nil
        end
      end
      -- local numRecords = #self._latencyHistory
      -- local minLatencyIndex = math.ceil(1.00 * numRecords)
      -- local maxLatencyIndex = math.ceil(1.00 * numRecords)
      -- local minLatency
      -- local maxLatency
      -- for i = #self._latencyHistory, 1, -1 do
      --   local record = self._latencyHistory[i]
      --   if i == minLatencyIndex then
      --     minLatency = record.latency
      --   end
      --   if i == maxLatencyIndex then
      --     maxLatency = record.latency
      --   end
      --   if record.time < self._time - LATENCY_WINDOW then
      --     table.remove(self._latencyHistory, i)
      --   end
      -- end
      -- if numRecords > 0 and (numRecords >= 20 or self._time >= 2.00) then
      --   local latency = self:getLatency()
      --   if minLatency > latency then
      --     self:_setLatency(minLatency)
      --   elseif maxLatency < latency then
      --     self:_setLatency(maxLatency)
      --   end
      -- end
    end,
    draw = function(self, x, y, width, height)
      -- Remember what graphics we started with
      local font = love.graphics.getFont()
      local r, g, b, a = love.graphics.getColor()
      love.graphics.setFont(FONT)
      -- Draw background
      love.graphics.setColor(0.2, 0.2, 0.2)
      love.graphics.rectangle('fill', x, y, width, height)
      -- Draw latency numbers and graph of network traffic
      love.graphics.setColor(1, 1, 0)
      local latency = math.floor(1000 * self:getLatency())
      local framesOfLatency = math.ceil(60 * self:getLatency())
      if height <= 25 then
        if width >= 200 then
          love.graphics.print('Latency: ' .. latency .. 'ms (' .. framesOfLatency .. ' frames)', x + 5, y + height / 2 - 5)
          self:_drawNetworkTraffic(x + 130, y + 4, width - 133, height - 7)
        elseif width >= 120 then
          love.graphics.print('Latency: ' .. latency .. 'ms', x + 5, y + height / 2 - 5)
          self:_drawNetworkTraffic(x + 65, y + 4, width - 68, height - 7)
        else
          love.graphics.print('Latency: ' .. latency .. 'ms', x + 5, y + height / 2 - 5)
        end
      elseif height <= 50 then
        love.graphics.print('Latency: ' .. latency .. 'ms', x + 5, y + height / 2 - 10)
        love.graphics.print('(' .. framesOfLatency .. ' frames)', x + 5, y + height / 2)
        if width >= 140 then
          self:_drawNetworkTraffic(x + 85, y + 4, width - 88, height - 7)
        end
      else
        if width >= 150 then
          love.graphics.print('Latency: ' .. latency .. 'ms (' .. framesOfLatency .. ' frames)', x + 5, y + 4)
          -- if width >= 190 then
          --   self:_drawReluctance(x + 150, y + 4, width - 153, 10)
          -- end
          self:_drawNetworkTraffic(x + 5, y + 18, width - 8, height - 21)
        else
          love.graphics.print('Latency: ' .. latency .. 'ms', x + 5, y + 4)
          love.graphics.print('(' .. framesOfLatency .. ' frames)',x + 5, y + 14)
          self:_drawNetworkTraffic(x + 5, y + 28, width - 8, height - 31)
        end
      end
      -- Set the color back to what it used to be
      love.graphics.setFont(font)
      love.graphics.setColor(r, g, b, a)
    end,
    -- _drawReluctance = function(self, x, y, width, height)
    --   love.graphics.setColor(0.35, 0.2, 0.65)
    --   love.graphics.rectangle('line', x, y, width, height)
    --   love.graphics.rectangle('fill', x, y, width * math.min(self._reluctance / LATENCY_WINDOW, 1.00), height)
    -- end,
    _drawNetworkTraffic = function(self, x, y, width, height)
      -- Figure out the maximum latency in recent history
      local maxLatency
      for _, record in ipairs(self._latencyHistory) do
        if record.time > self._time - LATENCY_WINDOW and (not maxLatency or record.latency > maxLatency) then
          maxLatency = record.latency
        end
      end
      for _, record in ipairs(self._latencyGuessHistory) do
        if (not record.endTime or record.endTime > self._time - LATENCY_WINDOW) and (not maxLatency or record.latency > maxLatency) then
          maxLatency = record.latency
        end
      end
      -- Figure out how many labels we should have on the y-axis
      local numYLabels
      if height >= 150 then
        numYLabels = 5
      elseif height >= 60 then
        numYLabels = 4
      elseif height >= 35 then
        numYLabels = 3
      else
        numYLabels = 2
      end
      local labelStep = math.ceil(1000 * maxLatency / (numYLabels - 1) / 50) * 50
      local maxYValue = (numYLabels - 1) * labelStep
      local yStep = (height - 7.5 * numYLabels) / (numYLabels - 1)
      local maxLabelLength = #('' .. maxYValue)
      -- Draw the area that would be claimed by lowering latency
      love.graphics.setColor(0.35, 0.35, 0.2)
      if self._bestLowerLatency then
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._bestLowerLatencyDuration / LATENCY_WINDOW)
        local top = y + height - (height - 5) * 1000 * self:getLatency() / maxYValue
        local bottom = y + height - (height - 5) * 1000 * self._bestLowerLatency / maxYValue
        love.graphics.rectangle('fill', left, top, right - left, bottom - top)
      end
      -- Draw the area that is lost by not raising latency
      love.graphics.setColor(0.5, 0.2, 0.2)
      if self._bestHigherLatency then
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._bestHigherLatencyDuration / LATENCY_WINDOW)
        local top = y + height - (height - 5) * 1000 * self._bestHigherLatency / maxYValue
        local bottom = y + height - (height - 5) * 1000 * self:getLatency() / maxYValue
        love.graphics.rectangle('fill', left, top, right - left, bottom - top)
      end
      -- Draw the labels on the Y axis
      love.graphics.setColor(0.8, 0.8, 0.8)
      if height >= 25 then
        for i = 1, numYLabels do
          local text = '' .. (labelStep * (i - 1))
          love.graphics.print(text, x + 5 * (maxLabelLength - #text), y + height - 7.5 * i - yStep * (i - 1))
        end
      end
      -- Draw a vertical line for each latency record
      for _, record in ipairs(self._latencyHistory) do
        if record.time > self._time - LATENCY_WINDOW then
          local h = (height - 5) * 1000 * record.latency / maxYValue
          local recordX = x + width - (width - 5 * maxLabelLength - 3) * ((self._time - record.time) / LATENCY_WINDOW)
          local recordY = y + height - h
          -- if 
          if record.type == 'rejection' then
            love.graphics.setColor(0.8, 0.3, 0.3)
          else
            love.graphics.setColor(0.8, 0.8, 0.8)
          end
          love.graphics.rectangle('fill', recordX, recordY, 1.1, h)
        end
      end
      -- Draw a yellow horizontal line to represent the latency history
      love.graphics.setColor(1, 1, 0)
      for _, record in ipairs(self._latencyGuessHistory) do
        if not record.endTime or record.endTime > self._time - LATENCY_WINDOW then
          local h = (height - 5) * 1000 * record.latency / maxYValue
          local startX = width - (width - 5 * maxLabelLength - 3) * (math.min(LATENCY_WINDOW, self._time - record.startTime) / LATENCY_WINDOW)
          local endX = width - (width - 5 * maxLabelLength - 3) * ((self._time - (record.endTime or self._time)) / LATENCY_WINDOW)
          local dy = height - h
          love.graphics.line(x + startX, y + dy, x + endX, y + dy)
        end
      end
    end,
    getLatency = function(self)
      return self._latencyGuessHistory[#self._latencyGuessHistory].latency
    end,
    _setLatency = function(self, latency)
      local lastRecord = self._latencyGuessHistory[#self._latencyGuessHistory]
      lastRecord.endTime = self._time
      table.insert(self._latencyGuessHistory, {
        startTime = self._time,
        latency = latency
      })
      self._lastLatencyChangeTime = self._time
      -- self._reluctance = self._reluctance + 2.50
    end,
    record = function(self, latency, type)
      table.insert(self._latencyHistory, { time = self._time, latency = latency, type = type })
    end,
    onLatencyChange = function(self, callback) end
  }
end

return LatencyGuesstimator
