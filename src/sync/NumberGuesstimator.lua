local NumberGuesstimator = {}

function NumberGuesstimator:new(params)
  params = params or {}
  local timeWindow = params.timeWindow or 20.00
  local maxReluctance = params.maxReluctance or 20.00
  local lowerGuessWeight = params.lowerGuessWeight or 0.55
  local raiseGuessWeight = params.raiseGuessWeight or 0.15
  local reluctanceMult = params.reluctanceMult or 5.00

  return {
    records = {},
    guesses = { { value = 0.00, startTime = 0.00 } },
    reluctance = 0.00,
    time = 0.00,
    timeWindow = timeWindow,
    maxReluctance = maxReluctance,
    lowerGuessWeight = lowerGuessWeight,
    raiseGuessWeight = raiseGuessWeight,
    reluctanceMult = reluctanceMult,
    lastGuessTime = 0.00,
    bestLowerGuess = nil,
    bestLowerGuessDuration = nil,
    bestHigherGuess = nil,
    bestHigherGuessDuration = nil,
    spikeQuota = 0.00,
    update = function(self, dt)
      self.time = self.time + dt
      self.spikeQuota = math.min(3, self.spikeQuota + dt / 6.50)
      self.reluctance = math.max(0, self.reluctance - dt)
      local bestGuess = self:getBestGuess()
      -- Calculate what the best value would be to lower or raise to
      local lowerGuess
      local lowerGuessDuration
      local isFindingLowerLatencies = true
      local bestHigherGuessRecord
      self.bestLowerGuess = nil
      self.bestLowerGuessDuration = nil
      self.bestHigherGuess = nil
      self.bestHigherGuessDuration = nil
      -- TODO remove records
      for i = #self.records, 1, -1 do
        local record = self.records[i]
        if record.time > self.time - self.timeWindow and record.time > self.lastGuessTime and not record.isAnomaly then
          -- Find higher latencies
          if record.value >= bestGuess then
            isFindingLowerLatencies = false
            if not self.bestHigherGuess or record.value >= self.bestHigherGuess then
              self.bestHigherGuess = record.value
              self.bestHigherGuessDuration = self.time - record.time
              bestHigherGuessRecord = record
            elseif record.value + 0.008 >= self.bestHigherGuess then
              self.bestHigherGuessDuration = self.time - record.time
              bestHigherGuessRecord = record
            end
          -- Find lower latencies
          elseif isFindingLowerLatencies then
            if not lowerGuess then
              lowerGuess = record.value
            elseif record.value > lowerGuess then
              if not self.bestLowerGuess or (bestGuess - self.bestLowerGuess) * self.bestLowerGuessDuration < (bestGuess - lowerGuess) * lowerGuessDuration then
                self.bestLowerGuess = lowerGuess
                self.bestLowerGuessDuration = lowerGuessDuration
              end
              lowerGuess = record.value
            end
            lowerGuessDuration = self.time - record.time
          end
        end
      end
      if lowerGuess and (not self.bestLowerGuess or (bestGuess - self.bestLowerGuess) * self.bestLowerGuessDuration < (bestGuess - lowerGuess) * lowerGuessDuration)then
        self.bestLowerGuess = lowerGuess
        self.bestLowerGuessDuration = lowerGuessDuration
      end
      if self.bestHigherGuess and self.bestHigherGuessDuration > 0.50 and (self.bestHigherGuess + 0.001 - bestGuess) * self.bestHigherGuessDuration > self.raiseGuessWeight * (1 + self.reluctanceMult * self.reluctance / self.maxReluctance) then
        if self.spikeQuota >= 1.00 then
          bestHigherGuessRecord.isAnomaly = true
          self.spikeQuota = self.spikeQuota - 1.00
        else
          self:_setBestGuess(self.bestHigherGuess + 0.001)
          self.bestHigherGuess = nil
          self.bestHigherGuessDuration = nil
        end
      elseif self.bestLowerGuess and self.bestLowerGuessDuration > 1.00 and (self.bestLowerGuessDuration >= self.timeWindow - 0.50 or (bestGuess - self.bestLowerGuess) * self.bestLowerGuessDuration > self.lowerGuessWeight * (1 + self.reluctanceMult * self.reluctance / self.maxReluctance)) then
        if bestGuess - self.bestLowerGuess > 0.008 then
          self:_setBestGuess(self.bestLowerGuess)
          self.bestLowerGuess = nil
          self.bestLowerGuessDuration = nil
        end
      end
    end,
    getBestGuess = function(self)
      return self.guesses[#self.guesses].value
    end,
    _setBestGuess = function(self, value)
      local lastRecord = self.guesses[#self.guesses]
      lastRecord.endTime = self.time
      table.insert(self.guesses, {
        startTime = self.time,
        value = value
      })
      self.lastGuessTime = self.time
      self.reluctance = self.maxReluctance
    end,
    record = function(self, value, metadata)
      local record = metadata or {}
      record.time = self.time
      record.value = value
      if #self.guesses == 1 and #self.records == 0 then
        self.guesses[1].value = value
      end
      table.insert(self.records, record)
    end
  }
end

return NumberGuesstimator
