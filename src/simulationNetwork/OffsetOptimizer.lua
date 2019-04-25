local OffsetOptimizer = {}
function OffsetOptimizer:new(params)
  params = params or {}
  local numFramesOfHistory = params.numFramesOfHistory or 150
  local minPermissableOffset = params.minPermissableOffset or 0
  local maxPermissableOffset = params.maxPermissableOffset or 1
  local minOffsetBeforeImmediateCorrection = params.minOffsetBeforeImmediateCorrection or nil
  local maxOffsetBeforeImmediateCorrection = params.maxOffsetBeforeImmediateCorrection or nil
  local maxSequentialFramesWithoutRecords = params.maxSequentialFramesWithoutRecords or 15

  local optimizer = {
    -- Private config vars
    _numFramesOfHistory = numFramesOfHistory,
    _minPermissableOffset = minPermissableOffset,
    _maxPermissableOffset = maxPermissableOffset,
    _minOffsetBeforeImmediateCorrection = minOffsetBeforeImmediateCorrection,
    _maxOffsetBeforeImmediateCorrection = maxOffsetBeforeImmediateCorrection,
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
      local offset = nil
      for i = 1, #self._records do
        if self._records[i] and (offset == nil or self._records[i] < offset) then
          offset = self._records[i]
        end
      end
      if offset and ((self._minOffsetBeforeImmediateCorrection and offset < self._minOffsetBeforeImmediateCorrection) or (self._maxOffsetBeforeImmediateCorrection and offset > self._maxOffsetBeforeImmediateCorrection)) then
        return offset
      elseif offset and #self._records >= self._numFramesOfHistory and (offset < self._minPermissableOffset or offset > self._maxPermissableOffset) then
        return offset
      else
        return 0
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
