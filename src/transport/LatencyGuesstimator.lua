local LatencyGuesstimator = {}

local FONT = love.graphics.newFont(8)

function LatencyGuesstimator:new(params)
  params = params or {}

  return {
    _time = 0.00,
    _frame = 0,
    _records = {},
    _latencyHistory = { { latency = 0.5, startTime = 0.00 } },
    update = function(self, dt)
      self._time = self._time + dt
    end,
    moveForwardOneFrame = function(self, dt)
      self._frame = self._frame + 1
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
    _drawNetworkTraffic = function(self, x, y, width, height)
      if #self._records > 0 then
        -- Figure out the maximum latency in recent history
        local maxLatency
        for _, record in ipairs(self._records) do
          if record.time > self._time - 5.00 and (not maxLatency or record.latency > maxLatency) then
            maxLatency = record.latency
          end
        end
        for _, record in ipairs(self._latencyHistory) do
          if (not record.endTime or record.endTime > self._time - 5.00) and (not maxLatency or record.latency > maxLatency) then
            maxLatency = record.latency
          end
        end
        -- maxLatency = math.max(maxLatency, self._latency)
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
        -- Draw the labels on the Y axis
        love.graphics.setColor(0.8, 0.8, 0.8)
        if height >= 25 then
          for i = 1, numYLabels do
            local text = '' .. (labelStep * (i - 1))
            love.graphics.print(text, x + 5 * (maxLabelLength - #text), y + height - 7.5 * i - yStep * (i - 1))
          end
        end
        -- Draw a white vertical line for each latency record
        love.graphics.setColor(0.8, 0.8, 0.8)
        for _, record in ipairs(self._records) do
          if record.time > self._time - 5.00 then
            local h = (height - 5) * 1000 * record.latency / maxYValue
            local dx = width - (width - 5 * maxLabelLength - 3) * ((self._time - record.time) / 5.00)
            local dy = height - h
            love.graphics.rectangle('fill', x + dx, y + dy, 1, h)
          end
        end
        -- Draw a yellow horizontal line to represent the latency history
        love.graphics.setColor(1, 1, 0)
        for _, record in ipairs(self._latencyHistory) do
          if not record.endTime or record.endTime > self._time - 5.00 then
            local h = (height - 5) * 1000 * record.latency / maxYValue
            local startX = width - (width - 5 * maxLabelLength - 3) * (math.min(5.00, self._time - record.startTime) / 5.00)
            local endX = width - (width - 5 * maxLabelLength - 3) * ((self._time - (record.endTime or self._time)) / 5.00)
            local dy = height - h
            love.graphics.line(x + startX, y + dy, x + endX, y + dy)
          end
        end
        -- love.graphics.setColor(1, 1, 0)
        -- local h = (height - 5) * 1000 * self._latency / maxYValue
        -- love.graphics.line(x + 5 * maxLabelLength + 3, y + height - h, x + width, y + height - h)
      end
    end,
    getLatency = function(self)
      return self._latencyHistory[#self._latencyHistory].latency
    end,
    _setLatency = function(self, latency)
      local lastRecord = self._latencyHistory[#self._latencyHistory]
      lastRecord.endTime = self._time
      table.insert(self._latencyHistory, {
        startTime = self._time,
        latency = latency
      })
    end,
    record = function(self, latency, framesOfLatency)
      table.insert(self._records, { time = self._time, frame = self._frame, latency = latency, framesOfLatency = framesOfLatency })
    end,
    onLatencyChange = function(self, callback) end
  }
end

return LatencyGuesstimator
