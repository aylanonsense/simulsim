local NumberGuesstimator = require('src/sync/NumberGuesstimator')

local FONT

local FrameOffsetGuesstimator = {}

function FrameOffsetGuesstimator:new(params)
  local numberGuesstimator = NumberGuesstimator:new(params)

  local frameOffsetGuesstimator = {
    _numberGuesstimator = numberGuesstimator,
    _changeFrameOffsetCallbacks = {},
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
      local latency = math.floor(1000 * self:getFrameOffset())
      local framesOfLatency = math.ceil(60 * self:getFrameOffset())
      self:_drawNetworkTraffic(x + 4, y + 4, width - 7, height - 7)
      -- Set the color back to what it used to be
      love.graphics.setFont(font)
      love.graphics.setColor(r, g, b, a)
    end,
    _drawNetworkTraffic = function(self, x, y, width, height)
      local time = self._numberGuesstimator.time
      local timeWindow = self._numberGuesstimator.timeWindow
      -- Figure out the maximum value in recent history
      local minValue
      local maxValue
      for _, record in ipairs(self._numberGuesstimator.records) do
        if record.time > time - timeWindow then
          if not maxValue or record.value > maxValue then
            maxValue = record.value
          end
          if not minValue or record.value < minValue then
            minValue = record.value
          end
        end
      end
      for _, record in ipairs(self._numberGuesstimator.guesses) do
        if not record.endTime or record.endTime > time - timeWindow then
          if not maxValue or record.value > maxValue then
            maxValue = record.value
          end
          if not minValue or record.value < minValue then
            minValue = record.value
          end
        end
      end
      local range = maxValue - minValue
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
      if 60 * range > 350 then
        minLabelStep = 50
      elseif 60 * range > 100 then
        minLabelStep = 25
      elseif 60 * range > 50 then
        minLabelStep = 10
      elseif 60 * range > 25 then
        minLabelStep = 5
      elseif 60 * range > 10 then
        minLabelStep = 2
      else
        minLabelStep = 1
      end
      local minYValue = math.floor(60 * minValue / minLabelStep) * minLabelStep
      local labelStep = math.ceil((60 * maxValue - minYValue) / (numYLabels - 1) / minLabelStep) * minLabelStep
      local maxYValue = (numYLabels - 1) * labelStep + minYValue
      local yStep = (height - 7.5 * numYLabels) / (numYLabels - 1)
      local maxLabelLength = 3 -- math.max(#('' .. minYValue), #('' .. maxYValue))
      local axisRange = maxYValue - minYValue
      -- Draw the area that would be claimed by lowering latency
      if self._numberGuesstimator.bestLowerGuess then
        love.graphics.setColor(0.25, 0.35, 0.2)
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._numberGuesstimator.bestLowerGuessDuration / timeWindow)
        local top = y + height - (height - 5) * (self:getFrameOffset() - minYValue) / (maxYValue - minYValue)
        local bottom = y + height - (height - 5) * (60 * self._numberGuesstimator.bestLowerGuess - minYValue) / (maxYValue - minYValue)
        love.graphics.rectangle('fill', left, top, right - left, bottom - top)
      end
      -- Draw the area that is lost by not raising latency
      if self._numberGuesstimator.bestHigherGuess then
        love.graphics.setColor(0.2, 0.30, 0.35)
        local right = x + width
        local left = right - (width - 5 * maxLabelLength - 3) * (self._numberGuesstimator.bestHigherGuessDuration / timeWindow)
        local top = y + height - (height - 5) * (60 * self._numberGuesstimator.bestHigherGuess - minYValue) / (maxYValue - minYValue)
        local bottom = y + height - (height - 5) * (self:getFrameOffset() - minYValue) / (maxYValue - minYValue)
        love.graphics.rectangle('fill', left, top, right - left, bottom - top)
      end
      -- -- Draw the labels on the Y axis
      -- love.graphics.setColor(0.8, 0.8, 0.8)
      -- if height >= 25 then
      --   for i = 1, numYLabels do
      --     local text = '' .. (labelStep * (i - 1) + minYValue)
      --     love.graphics.print(text, x + 5 * (maxLabelLength - #text), y + height - 7.5 * i - yStep * (i - 1))
      --   end
      -- end
      -- Draw a vertical line for each record
      for _, record in ipairs(self._numberGuesstimator.records) do
        if record.time > time - timeWindow then
          local h = (height - 5) * (60 * record.value - minYValue) / (maxYValue - minYValue)
          local recordX = x + width - (width - 5 * maxLabelLength - 3) * ((time - record.time) / timeWindow)
          local recordY = y + height - h
          if record.isAnomaly then
            love.graphics.setColor(0.5, 0.5, 0.5)
          else
            love.graphics.setColor(0.8, 0.8, 0.8)
          end
          love.graphics.rectangle('fill', recordX, recordY, 1.1, h)
        end
      end
      -- Draw a green horizontal line to represent the guess history
      love.graphics.setColor(0.3, 0.9, 0.2)
      for _, record in ipairs(self._numberGuesstimator.guesses) do
        if not record.endTime or record.endTime > time - timeWindow then
          local h = (height - 5) * (60 * record.value - minYValue) / (maxYValue - minYValue)
          local startX = width - (width - 5 * maxLabelLength - 3) * (math.min(timeWindow, time - record.startTime) / timeWindow)
          local endX = width - (width - 5 * maxLabelLength - 3) * ((time - (record.endTime or time)) / timeWindow)
          local dy = height - h
          love.graphics.line(x + startX, y + dy, x + endX, y + dy)
        end
      end
    end,
    getFrameOffset = function(self)
      return 60 * self._numberGuesstimator:getBestGuess()
    end,
    setFrameOffset = function(self, frameOffset)
      return self._numberGuesstimator:setBestGuess(frameOffset / 60)
    end,
    hasSetFrameOffset = function(self)
      return self._numberGuesstimator.hasMadeGuess
    end,
    record = function(self, frameOffset, type)
      self._numberGuesstimator:record(frameOffset / 60, { type = type })
    end,
    onChangeFrameOffset = function(self, callback)
      table.insert(self._changeFrameOffsetCallbacks, callback)
    end,
    _handleChangeGuess = function(self, value, prevValue)
      for _, callback in ipairs(self._changeFrameOffsetCallbacks) do
        callback(60 * value, prevValue and (60 * prevValue) or prevValue)
      end
    end
  }

  numberGuesstimator:onChangeGuess(function(value, prevValue)
    frameOffsetGuesstimator:_handleChangeGuess(value, prevValue)
  end)

  return frameOffsetGuesstimator
end

return FrameOffsetGuesstimator
