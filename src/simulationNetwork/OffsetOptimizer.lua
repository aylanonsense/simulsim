local OffsetOptimizer = {}
function OffsetOptimizer:new(params)
  params = params or {}
  local numFramesOfHistory = params.numFramesOfHistory or 150
  local minimumAllowedOffset = params.minimumAllowedOffset or 0
  local maximumAllowedOffset = params.maximumAllowedOffset or 1
  local maxSequentialFramesWithoutRecords = params.maxSequentialFramesWithoutRecords or 15

  local optimizer = {
    -- Private config vars
    _numFramesOfHistory = numFramesOfHistory,
    _minimumAllowedOffset = minimumAllowedOffset,
    _maximumAllowedOffset = maximumAllowedOffset,
    _maxSequentialFramesWithoutRecords = maxSequentialFramesWithoutRecords,

    -- Private vars
    _records = {},

    -- Public methods
    -- Records an offset, e.g. negative means late, positive means early
    recordOffset = function(self, offset)
      if not self._records[1] or self._records[1] > offset then
        self._records[1] = offset
      end
    end,
    -- Gets the amount the optimizer would recommend adjusting by, negative means slow down, positive means speed up
    getRecommendedAdjustment = function(self)
      local minOffset = nil
      for i = 1, #self._records do
        if self._records[i] and (minOffset == nil or self._records[i] < minOffset) then
          minOffset = self._records[i]
        end
      end
      minOffset = minOffset or 0
      if #self._records >= self._numFramesOfHistory or minOffset < self._minimumAllowedOffset then
        if self._minimumAllowedOffset <= minOffset and minOffset <= self._maximumAllowedOffset then
          return 0
        else
          return minOffset
        end
      else
        return 0
      end
    end,
    applyAdjustment = function(self, adjustment)
      for i = 1, #self._records do
        if self._records[i] then
          self._records[i] = self._records[i] - adjustment
        end
      end
    end,
    reset = function(self)
      self._records = {}
    end,
    update = function(self, dt, df)
      -- If we haven't had any records for a while, we should keep the historical records around for longer
      local numSequentialFramesWithoutRecords = 0
      for i = 1, #self._records do
        if not self._records[i] then
          numSequentialFramesWithoutRecords = numSequentialFramesWithoutRecords + 1
        else
          break
        end
      end
      if numSequentialFramesWithoutRecords < self._maxSequentialFramesWithoutRecords  then
        -- Get rid of the older records and make space for newer ones
        for i = self._numFramesOfHistory, 1, -1 do
          if i <= df then
            self._records[i] = false
          else
            self._records[i] = self._records[i - df]
          end
        end
      end
    end
  }

  return optimizer
end

return OffsetOptimizer
