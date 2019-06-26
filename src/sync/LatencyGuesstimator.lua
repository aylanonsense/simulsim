local NumberGuesstimator = require('src/sync/NumberGuesstimator')

local FONT

local LatencyGuesstimator = {}

function LatencyGuesstimator:new(params)
  local numberGuesstimator = NumberGuesstimator:new(params)

  local latencyGuesstimator = {
    _numberGuesstimator = numberGuesstimator,
    _changeLatencyCallbacks = {},
    update = function(self, dt)
      self._numberGuesstimator:update(dt)
    end,
    draw = function(self, x, y, width, height)
      -- Remember what graphics we started with
      local font = love.graphics.getFont()
      local r, g, b, a = love.graphics.getColor()
      if not FONT then
        FONT = love.graphics.newFont(8)
      end
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
          if width >= 190 then
            self:_drawReluctance(x + 150, y + 4, width - 153, 10)
          end
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
    _drawReluctance = function(self, x, y, width, height)
      love.graphics.setColor(0.35, 0.2, 0.65)
      love.graphics.rectangle('line', x, y, width, height)
      love.graphics.rectangle('fill', x, y, width * math.min(self._numberGuesstimator.reluctance / self._numberGuesstimator.maxReluctance, 1.00), height)
    end,
    _drawNetworkTraffic = function(self, x, y, width, height)
      local time = self._numberGuesstimator.time
      local timeWindow = self._numberGuesstimator.timeWindow
      -- Figure out the maximum latency in recent history
      local maxLatency
      for _, record in ipairs(self._numberGuesstimator.records) do
        if record.time > time - timeWindow and (not maxLatency or record.value > maxLatency) then
          maxLatency = record.value
        end
      end
      for _, record in ipairs(self._numberGuesstimator.guesses) do
        if (not record.endTime or record.endTime > time - timeWindow) and (not maxLatency or record.value > maxLatency) then
          maxLatency = record.value
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
      local minLabelStep
      if maxLatency > 350 then
        minLabelStep = 50
      elseif maxLatency > 100 then
        minLabelStep = 25
      elseif maxLatency > 50 then
        minLabelStep = 10
      else
        minLabelStep = 5
      end
      local labelStep = math.ceil(1000 * maxLatency / (numYLabels - 1) / minLabelStep) * minLabelStep
      local maxYValue = (numYLabels - 1) * labelStep
      local yStep = (height - 7.5 * numYLabels) / (numYLabels - 1)
      local maxLabelLength = #('' .. maxYValue)
      -- Draw the area that would be claimed by lowering latency
      if self._numberGuesstimator.bestLowerGuess then
        love.graphics.setColor(0.33, 0.33, 0.2)
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._numberGuesstimator.bestLowerGuessDuration / timeWindow)
        local top = y + height - (height - 5) * 1000 * self:getLatency() / maxYValue
        local bottom = y + height - (height - 5) * 1000 * self._numberGuesstimator.bestLowerGuess / maxYValue
        love.graphics.rectangle('fill', left, top, right - left, bottom - top)
      end
      -- Draw the area that is lost by not raising latency
      if self._numberGuesstimator.bestHigherGuess then
        love.graphics.setColor(0.4, 0.25, 0.2)
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._numberGuesstimator.bestHigherGuessDuration / timeWindow)
        local top = y + height - (height - 5) * 1000 * self._numberGuesstimator.bestHigherGuess / maxYValue
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
      for _, record in ipairs(self._numberGuesstimator.records) do
        if record.time > time - timeWindow then
          local h = (height - 5) * 1000 * record.value / maxYValue
          local recordX = x + width - (width - 5 * maxLabelLength - 3) * ((time - record.time) / timeWindow)
          local recordY = y + height - h
          if record.isAnomaly then
            love.graphics.setColor(0.5, 0.5, 0.5)
          elseif record.type == 'rejection' then
            love.graphics.setColor(0.8, 0.3, 0.3)
          else
            love.graphics.setColor(0.8, 0.8, 0.8)
          end
          love.graphics.rectangle('fill', recordX, recordY, 1.1, h)
        end
      end
      -- Draw a yellow horizontal line to represent the latency history
      love.graphics.setColor(1, 1, 0)
      for _, record in ipairs(self._numberGuesstimator.guesses) do
        if not record.endTime or record.endTime > time - timeWindow then
          local h = (height - 5) * 1000 * record.value / maxYValue
          local startX = width - (width - 5 * maxLabelLength - 3) * (math.min(timeWindow, time - record.startTime) / timeWindow)
          local endX = width - (width - 5 * maxLabelLength - 3) * ((time - (record.endTime or time)) / timeWindow)
          local dy = height - h
          love.graphics.line(x + startX, y + dy, x + endX, y + dy)
        end
      end
    end,
    getLatency = function(self)
      return self._numberGuesstimator:getBestGuess()
    end,
    setLatency = function(self, latency)
      return self._numberGuesstimator:setBestGuess(latency)
    end,
    hasSetLatency = function(self)
      return self._numberGuesstimator.hasMadeGuess
    end,
    record = function(self, latency, type)
      self._numberGuesstimator:record(latency, { type = type })
    end,
    onChangeLatency = function(self, callback)
      table.insert(self._changeLatencyCallbacks, callback)
    end,
    _handleChangeGuess = function(self, value, prevValue)
      for _, callback in ipairs(self._changeLatencyCallbacks) do
        callback(value, prevValue)
      end
    end
  }

  numberGuesstimator:onChangeGuess(function(value, prevValue)
    latencyGuesstimator:_handleChangeGuess(value, prevValue)
  end)

  return latencyGuesstimator
end

return LatencyGuesstimator
