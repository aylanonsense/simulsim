local OffsetOptimizer = {}
function OffsetOptimizer:new(params)
  params = params or {}
  local numFramesOfHistory = params.numFramesOfHistory or 180
  local minPermissableOffset = params.minPermissableOffset or 0
  local maxPermissableOffset = params.maxPermissableOffset or 2
  local minOffsetBeforeImmediateCorrection = params.minOffsetBeforeImmediateCorrection or nil
  local maxOffsetBeforeImmediateCorrection = params.maxOffsetBeforeImmediateCorrection or nil
  local maxSequentialFramesWithoutRecords = params.maxSequentialFramesWithoutRecords or 8
  local numSmallestRecordsToIgnore = numSmallestRecordsToIgnore or 5
  local numLargestRecordsToIgnore = numLargestRecordsToIgnore or 5

  local optimizer = {
    -- Private config vars
    _numFramesOfHistory = numFramesOfHistory,
    _minPermissableOffset = minPermissableOffset,
    _maxPermissableOffset = maxPermissableOffset,
    _minOffsetBeforeImmediateCorrection = minOffsetBeforeImmediateCorrection,
    _maxOffsetBeforeImmediateCorrection = maxOffsetBeforeImmediateCorrection,
    _maxSequentialFramesWithoutRecords = maxSequentialFramesWithoutRecords,
    _numSmallestRecordsToIgnore = numSmallestRecordsToIgnore,
    _numLargestRecordsToIgnore = numLargestRecordsToIgnore,

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
      -- Get a list of all the offsets
      local actualRecords = {}
      for i = 1, #self._records do
        if self._records[i] then
          table.insert(actualRecords, self._records[i])
        end
      end
      -- We don't yet have enough offsets to make a recommendation
      if #actualRecords <= self._numSmallestRecordsToIgnore + self._numLargestRecordsToIgnore then
        return nil
      end
      -- Figure out the smallest valid offset
      table.sort(actualRecords)
      local offset = actualRecords[self._numSmallestRecordsToIgnore + 1]
      -- Return an immediate result if it exceeds our immediate correction limits
      if (self._minOffsetBeforeImmediateCorrection and offset < self._minOffsetBeforeImmediateCorrection) or (self._maxOffsetBeforeImmediateCorrection and offset > self._maxOffsetBeforeImmediateCorrection) then
        return offset
      -- Otherwise wait until we have more records
      elseif #self._records < self._numFramesOfHistory then
        return nil
      -- If we have enough records and the adjustment is worth making, return the recommended adjustment
      elseif offset < self._minPermissableOffset or offset > self._maxPermissableOffset then
        return offset
      -- But if the adjustment is negligible, just return 0 (meaning no recommended adjustment)
      else
        return 0
      end
    end,
    reset = function(self)
      self._records = {}
    end,
    moveForwardOneFrame = function(self, dt)
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
          if i <= 1 then
            self._records[i] = false
          else
            self._records[i] = self._records[i - 1]
          end
        end
      end
    end
  }

  return optimizer
end

return OffsetOptimizer
